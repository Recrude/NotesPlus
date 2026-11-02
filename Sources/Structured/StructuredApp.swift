import AppKit
import SwiftUI
import CryptoKit

struct StructuredDraft:Codable,Sendable {var base:CloudSnapshot;var document:CloudDocument}
struct StructuredHistory:Codable,Sendable {var latest:CloudSnapshot;var superseded:[String]}
final class StructuredJournal:@unchecked Sendable {
    private let queue=DispatchQueue(label:"dev.notesplus.structured.journal",qos:.utility)
    static func write<T:Encodable>(_ value:T,to url:URL)throws {
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        try JSONEncoder().encode(value).write(to:url,options:.atomic)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)
    }
    func store<T:Encodable & Sendable>(_ value:T,to url:URL)async throws {
        try await withCheckedThrowingContinuation{(c:CheckedContinuation<Void,Error>) in queue.async{do{try Self.write(value,to:url);c.resume()}catch{c.resume(throwing:error)}}}
    }
    func read<T:Decodable & Sendable>(_ type:T.Type,at url:URL)async->T? {
        await withCheckedContinuation{c in queue.async{c.resume(returning:(try? Data(contentsOf:url)).flatMap{try? JSONDecoder().decode(type,from:$0)})}}
    }
    func drafts(in folder:URL)async->[StructuredDraft] {
        await withCheckedContinuation{c in queue.async{
            let files=(try? FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil)) ?? []
            c.resume(returning:files.filter{$0.pathExtension=="json" && !$0.lastPathComponent.hasPrefix("history-")}.compactMap{url in (try? Data(contentsOf:url)).flatMap{try? JSONDecoder().decode(StructuredDraft.self,from:$0)}})
        }}
    }
    func remove(_ url:URL)async throws {try await withCheckedThrowingContinuation{(c:CheckedContinuation<Void,Error>) in queue.async{do{if FileManager.default.fileExists(atPath:url.path){try FileManager.default.removeItem(at:url)};c.resume()}catch{c.resume(throwing:error)}}}}
    func sync(_ drafts:[(StructuredDraft,URL)])throws {try queue.sync{for (draft,url) in drafts {try Self.write(draft,to:url)}}}
}
@MainActor final class CloudNoteState {
    var base:CloudSnapshot;var document:CloudDocument;var dirty=false;var generation=0
    var saving=false;var conflict:CloudSnapshot?;var superseded:[String]=[];var unsavedSince:Date?;var lastEdit=Date.distantPast;var lastAttempt=Date.distantPast
    init(_ base:CloudSnapshot){self.base=base;self.document=base.document}
}
@MainActor final class StructuredModel:ObservableObject {
    @Published var folders:[CloudFolder]=[]
    @Published var notes:[CloudSummary]=[]
    @Published var selectedFolderID:String?
    @Published var selectedID:String?
    @Published var search=""
    @Published var status="iCloud 연결이 필요합니다."
    @Published var connected=false
    @Published var loading=false
    @Published var revision=0
    @Published var pendingInput=false
    @Published var selectionError:String?
    let editor=StructuredEditorHandle()
    let client:any CloudRequesting
    let settings:EditorSettings
    private var states:[String:CloudNoteState]=[:]
    private var current:CloudNoteState? {selectedID.flatMap{states[$0]}}
    var snapshot:CloudSnapshot? {
        get{current?.base}
        set {if let v=newValue {selectedID=v.id;if let s=states[v.id]{s.base=v}else{states[v.id]=CloudNoteState(v)}}else{selectedID=nil}}
    }
    var document:CloudDocument {get{current?.document ?? CloudDocument(paragraphs:[CloudParagraph()])}set{current?.document=newValue}}
    var dirty:Bool {current?.dirty ?? false}
    var saving:Bool {current?.saving ?? false}
    var conflict:CloudSnapshot? {current?.conflict}
    var canEdit:Bool {snapshot != nil && snapshot?.readOnlyReason==nil}
    var visibleNotes:[CloudSummary] {
        let query=search.trimmingCharacters(in:.whitespacesAndNewlines)
        return notes.filter{(selectedFolderID==nil || $0.folderID==selectedFolderID) && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || (settings.searchScope != "title" && ($0.preview ?? "").localizedCaseInsensitiveContains(query)))}.sorted{a,b in
            let order:ComparisonResult=settings.sortBy=="title" ? a.title.localizedStandardCompare(b.title) : Date(timeIntervalSince1970:settings.sortBy=="created" ? a.created : a.modified ?? a.created).compare(Date(timeIntervalSince1970:settings.sortBy=="created" ? b.created : b.modified ?? b.created))
            if order == .orderedSame{return a.id<b.id};return settings.sortAscending ? order == .orderedAscending:order == .orderedDescending
        }
    }
    private var account:CloudAccount?
    private var login:CloudLogin?
    private var debounce:Task<Void,Never>?,journalTask:Task<Void,Never>?,poll:Task<Void,Never>?
    private var selectionToken=0,listLoading=false,refreshing=false
    private let disk=StructuredJournal(),support:URL
    private var lastList=Date.distantPast,lastRefresh=Date.distantPast
    init(client:any CloudRequesting=CloudClient(),account:CloudAccount?=nil,startTasks:Bool=true,support:URL?=nil,settings:EditorSettings?=nil) {
        self.client=client;self.account=account;self.connected=account != nil;self.settings=settings ?? EditorSettings()
        self.support=support ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("NotesPlus/Structured",isDirectory:true)
        try? FileManager.default.createDirectory(at:self.support,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        guard startTasks else{return}
        Task {
            for draft in await disk.drafts(in:self.support) {if states[draft.base.id]==nil{let s=CloudNoteState(draft.base);s.document=draft.document;s.dirty=true;s.unsavedSince=Date();states[s.base.id]=s}}
            if self.account==nil {self.account=await Task.detached(priority:.userInitiated){CloudKeychain.load()}.value}
            connected=self.account != nil
            if connected {await reloadList()}
        }
        poll=Task{[weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for:.seconds(1));guard !Task.isCancelled,let self else{return}
                for s in self.states.values where s.dirty && !s.saving && s.conflict==nil && Date().timeIntervalSince(s.lastAttempt)>=self.settings.autosaveMaxInterval {if self.current===s{self.editor.flush()};Task{await self.save(s)}}
                if !self.dirty && Date().timeIntervalSince(self.lastRefresh)>=self.settings.syncInterval {await self.refresh()}
                if Date().timeIntervalSince(self.lastList)>30 {await self.reloadList()}
            }
        }
    }
    func signIn() {
        if login==nil {login=CloudLogin(client:client);login?.onAccount={[weak self] a in guard let self else{return};self.account=a;self.connected=true;Task{await self.reloadList()}}}
        login?.show()
    }
    func reloadList() async {
        guard let account,!listLoading else{return};listLoading=true;defer{listLoading=false;lastList=Date()}
        do {
            let listing=try await client.request("list",account:account,as:CloudListing.self)
            folders=listing.folders;notes=listing.notes
            if selectedID==nil,selectionError==nil {
                let last=settings.restoreLastNote ? UserDefaults.standard.string(forKey:"structuredLastNote"):nil
                if let first=notes.first(where:{$0.id==last}) {await select(first.id)}
                else{status="iCloud 연결됨 · 폴더를 선택하고 새 메모를 만드세요."}
            }
        }catch{status=error.localizedDescription}
    }
    func chooseFolder(_ id:String?)async {selectedFolderID=id;selectionError=nil;if !visibleNotes.contains(where:{$0.id==selectedID}),let first=visibleNotes.first {await select(first.id)}}
    func select(_ id:String) async {
        guard id != selectedID,let account else{return}
        editor.flush();guard await preserveCurrent() else{return};debounce?.cancel()
        if let old=current,old.dirty {Task{await save(old)}}
        selectionToken+=1;let token=selectionToken;loading=true;selectionError=nil
        defer{if token==selectionToken {loading=false}}
        do {
            if states[id]==nil {
                let remote=try await client.request("read",account:account,payload:["id":id],as:CloudSnapshot.self)
                let history=await disk.read(StructuredHistory.self,at:historyURL(id))
                let s=CloudNoteState(history?.superseded.contains(remote.tag)==true ? history!.latest:remote)
                s.superseded=history?.superseded ?? []
                if let draft=await disk.read(StructuredDraft.self,at:draftURL(id)) {s.base=draft.base;s.document=draft.document;s.dirty=true;s.unsavedSince=Date();if remote.readOnlyReason != nil {s.base.readOnlyReason=remote.readOnlyReason}}
                states[id]=s
            }
            guard token==selectionToken else{return}
            editor.flush();guard await preserveCurrent() else{return}
            selectedID=id;pendingInput=false;revision+=1;UserDefaults.standard.set(id,forKey:"structuredLastNote")
            status=dirty ? "보관된 초안 복원 · 자동 저장 대기":"iCloud 동기화됨"
            if dirty {Task{await save()}}else{Task{await refresh()}}
        }catch {if token==selectionToken {selectionError=error.localizedDescription;status="메모를 불러오지 못했습니다. 작성 중인 초안은 보관됩니다."}}
    }
    func create() async {
        guard let account,!loading else{return};editor.flush();guard await preserveCurrent() else{return}
        let target=folders.contains(where:{$0.id==settings.defaultFolderID && !$0.shared}) ? settings.defaultFolderID:(folders.first(where:{$0.id==selectedFolderID && !$0.shared})?.id ?? folders.first(where:{!$0.shared})?.id)
        guard let target else{status="새 메모를 만들 iCloud 폴더가 없습니다.";return}
        if let old=current,old.dirty {Task{await save(old)}}
        selectionToken+=1;let token=selectionToken;loading=true;defer{if selectionToken==token{loading=false}}
        do {
            let note=try await client.request("create",account:account,payload:["folderID":target,"style":settings.newNoteStyle],as:CloudSnapshot.self)
            states[note.id]=CloudNoteState(note);notes.insert(CloudSummary(id:note.id,title:note.title,created:note.created,modified:note.modified,folderID:target),at:0)
            guard selectionToken==token else{return};editor.flush();guard await preserveCurrent() else{return}
            editor.focusOnLoad=true;selectedFolderID=target;selectedID=note.id;UserDefaults.standard.set(note.id,forKey:"structuredLastNote");selectionError=nil;pendingInput=false;revision+=1;status="새 메모 · 자동 저장"
        }catch{status=error.localizedDescription}
    }
    func inputBegan() {if !pendingInput{pendingInput=true};current?.lastEdit=Date()}
    func edited(_ document:CloudDocument) {
        guard let s=current,s.base.readOnlyReason==nil else{return}
        s.document=document;s.generation+=1;s.dirty=true;s.lastEdit=Date();s.unsavedSince=s.unsavedSince ?? Date();pendingInput=false
        status="입력 중 · 자동 저장 대기"
        journalTask?.cancel();journalTask=Task{try? await Task.sleep(for:.milliseconds(300));guard !Task.isCancelled else{return};_ = await preserve(s)}
        debounce?.cancel();debounce=Task{try? await Task.sleep(for:.seconds(settings.autosaveDelay));guard !Task.isCancelled else{return};await save(s)}
    }
    func save()async {editor.flush();if let s=current{await save(s)}}
    private func save(_ s:CloudNoteState)async {
        guard s.dirty,!s.saving,s.base.readOnlyReason==nil,let account else{return}
        if selectedID==s.base.id,editor.view?.hasMarkedText()==true{return}
        s.saving=true;s.lastAttempt=Date();objectWillChange.send()
        defer{s.saving=false;objectWillChange.send()}
        guard await preserve(s) else{return}
        let sent=s.document,version=s.generation,base=s.base
        do {
            var acknowledged:CloudSnapshot?,seenTags:[String]=[]
            for attempt in 0..<3 {
                let remote=try await client.request("read",account:account,payload:["id":base.id],as:CloudSnapshot.self)
                guard remote.readOnlyReason==nil else{throw CloudFailure(code:"PROTECTED",message:remote.readOnlyReason!)}
                // Conditional writes may only replace the exact source backed up here.
                try await disk.store(remote,to:backupURL(remote.id,tag:remote.tag));seenTags.append(remote.tag)
                let payload:[String:Any]=["id":base.id,"base":try object(base.document),"document":try object(sent),"expectedTag":remote.tag]
                do {acknowledged=try await client.request("save",account:account,payload:payload,as:CloudSnapshot.self);break}
                catch {if (error as? CloudFailure)?.code=="RETRY" && attempt<2 {continue};throw error}
            }
            guard var saved=acknowledged else{throw CloudFailure(code:"RETRY",message:"다른 기기의 저장을 기다립니다. 초안은 보관됩니다.")}
            remember(s,base.tag);for tag in seenTags where tag != saved.tag{remember(s,tag)}
            try await disk.store(StructuredHistory(latest:saved,superseded:s.superseded),to:historyURL(base.id))
            if s.generation==version && !(selectedID==base.id && pendingInput) {
                s.base=saved;s.dirty=false;s.unsavedSince=nil;s.conflict=nil
                let changed = !s.document.editorEquivalent(to:saved.document);s.document=saved.document
                if selectedID==base.id {if changed{revision+=1};status="iCloud 동기화됨"}
                try await disk.remove(draftURL(base.id))
            }else{saved.document=sent;s.base=saved;_ = await preserve(s);if selectedID==base.id{status="입력 중 · 이전 변경 저장됨"}}
            if let i=notes.firstIndex(where:{$0.id==base.id}){notes[i].title=saved.title;notes[i].modified=saved.modified;notes[i].preview=saved.document.paragraphs.dropFirst().map(\.text).joined(separator:" ").prefix(180).description}
        }catch {
            if (error as? CloudFailure)?.code=="CONFLICT" {s.conflict=try? await client.request("read",account:account,payload:["id":base.id],as:CloudSnapshot.self)}
            _ = await preserve(s);if selectedID==base.id{status=error.localizedDescription}
        }
    }
    func refresh()async {
        guard !refreshing,!loading,!pendingInput,let s=current,!s.dirty,!s.saving,let account,editor.view?.hasMarkedText() != true,Date().timeIntervalSince(s.lastEdit)>=settings.syncInterval else{return}
        refreshing=true;defer{refreshing=false;lastRefresh=Date()};let version=s.generation,base=s.base
        do {
            let remote=try await client.request("read",account:account,payload:["id":base.id],as:CloudSnapshot.self)
            guard current===s,s.generation==version,!pendingInput,!s.dirty,editor.view?.hasMarkedText() != true,!s.superseded.contains(remote.tag) else{return}
            if remote.tag != base.tag || !remote.document.editorEquivalent(to:s.document) || remote.readOnlyReason != base.readOnlyReason {
                let changed = !remote.document.editorEquivalent(to:s.document) || remote.readOnlyReason != base.readOnlyReason
                if remote.tag != base.tag{remember(s,base.tag)};s.base=remote
                if changed{s.document=remote.document;revision+=1}
                status="다른 기기의 변경을 불러왔습니다. 계속 편집할 수 있습니다."
                try await disk.store(StructuredHistory(latest:remote,superseded:s.superseded),to:historyURL(base.id))
            }
        }catch{if current===s{status="연결 대기 · 입력과 초안 보관은 계속됩니다."}}
    }
    func tableAction(_ action:String)async {
        editor.flush();guard let id=selectedID,canEdit else{return}
        let selection=editor.view?.selectedRange()
        await save()
        guard selectedID==id,!dirty,!pendingInput,editor.view?.selectedRange()==selection else{status="입력이 저장된 후 표 작업을 다시 선택해 주세요.";return}
        if action=="insert"{editor.view?.insertTable()}else{editor.view?.resizeTable(action)}
        editor.flush();await save()
    }
    func resolveConflict(useLocal:Bool)async {
        editor.flush();guard let s=current,let remote=s.conflict,remote.readOnlyReason==nil,await preserve(s) else{return}
        do {try await disk.store(StructuredDraft(base:s.base,document:s.document),to:support.appendingPathComponent("Conflicts/\(UUID().uuidString).json"));try await disk.store(remote,to:backupURL(remote.id,tag:remote.tag))}catch{status=error.localizedDescription;return}
        s.base=remote;s.conflict=nil
        if useLocal {s.dirty=true;await save(s)}else{s.document=remote.document;s.dirty=false;s.unsavedSince=nil;try? await disk.remove(draftURL(s.base.id));revision+=1;status="iCloud 버전을 불러왔습니다. 작성본은 보관 폴더에 남겨 두었습니다."}
        objectWillChange.send()
    }
    private func preserveCurrent()async->Bool {guard let s=current else{return true};return await preserve(s)}
    private func preserve(_ s:CloudNoteState)async->Bool {
        guard s.dirty else{return true}
        do{try await disk.store(StructuredDraft(base:s.base,document:s.document),to:draftURL(s.base.id));return true}catch{status="초안을 보관하지 못했습니다: \(error.localizedDescription)";return false}
    }
    @discardableResult func persistDraft()->Bool {
        editor.flush()
        do{try disk.sync(states.values.filter(\.dirty).map{(StructuredDraft(base:$0.base,document:$0.document),draftURL($0.base.id))});return true}catch{status="초안을 보관하지 못했습니다: \(error.localizedDescription)";return false}
    }
    func openSupportFolder(){NSWorkspace.shared.open(support.deletingLastPathComponent())}
    private func remember(_ s:CloudNoteState,_ tag:String){if !s.superseded.contains(tag){s.superseded.append(tag)};s.superseded=Array(s.superseded.suffix(40))}
    private func safe(_ id:String)->String{id.filter{$0.isLetter || $0.isNumber || $0=="-"}}
    private func historyURL(_ id:String)->URL{support.appendingPathComponent("history-"+safe(id)+".json")}
    private func draftURL(_ id:String)->URL{support.appendingPathComponent(safe(id)+".json")}
    private func backupURL(_ id:String,tag:String)->URL{support.appendingPathComponent("Backups/"+safe(id)+"/"+SHA256.hash(data:Data(tag.utf8)).map{String(format:"%02x",$0)}.joined()+".json")}
    private func object<T:Encodable>(_ value:T)throws->Any{try JSONSerialization.jsonObject(with:JSONEncoder().encode(value))}
}
