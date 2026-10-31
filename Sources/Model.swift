import AppKit
import SwiftUI
import CryptoKit

struct NoteFolder: Identifiable, Equatable {
    let id: String; let name: String; let account: String; let depth: Int; let shared: Bool; let count: Int
    init(_ d: [String: Any]) { id=d["id"] as? String ?? ""; name=d["name"] as? String ?? "폴더"; account=d["account"] as? String ?? ""; depth=(d["depth"] as? NSNumber)?.intValue ?? 0; shared=(d["shared"] as? NSNumber)?.boolValue ?? false; count=(d["count"] as? NSNumber)?.intValue ?? 0 }
}
struct NoteSummary: Identifiable, Equatable {
    let id: String; var name: String; var modified: Date; var created:Date
    init(_ d: [String: Any]) { id=d["id"] as? String ?? ""; name=d["name"] as? String ?? "새 메모"; modified=d["modified"] as? Date ?? .distantPast; created=d["created"] as? Date ?? modified }
}
struct NoteSnapshot {
    let id: String; let name: String; let html: String; var text: String; let modified: Date; let created:Date; var profile: EditingProfile; var document:NoteDocument?
    init(_ d: [String: Any]) {
        id=d["id"] as? String ?? ""; name=d["name"] as? String ?? ""; html=d["html"] as? String ?? ""; text=d["plain"] as? String ?? ""; modified=d["modified"] as? Date ?? .distantPast; created=d["created"] as? Date ?? modified
        profile=NoteCodec.profile(html: html, plaintext: text, locked:(d["locked"] as? NSNumber)?.boolValue ?? false, shared:(d["shared"] as? NSNumber)?.boolValue ?? false, attachments:(d["attachments"] as? NSNumber)?.intValue ?? 0)
        document=NoteCodec.document(html:html,plaintext:text,profile:profile)
        if profile.editable,document==nil {profile.reason="서식 구조를 보존할 수 없습니다 · 기본 메모에서 편집"}
    }
}
struct LocalDraft: Codable, Sendable { let id: String; let originalHTML: String; var text: String; let modified: Date; var pendingTitleTemplate:String? = nil; var document:NoteDocument? = nil }

@MainActor final class NotesModel: ObservableObject {
    @Published var folders: [NoteFolder] = []
    @Published var notes: [NoteSummary] = []
    @Published var selectedFolderID: String?
    @Published var selectedNoteID: String?
    @Published var snapshot: NoteSnapshot?
    // NSTextView owns live typing. This value never publishes per-keystroke invalidations.
    var text = ""
    @Published var editorLoadVersion:UInt = 0
    var editorDocument:NoteDocument?
    let editorBridge=EditorBridge()
    @Published var search = ""
    @Published var busy = false
    @Published var switching = false
    @Published var saving = false
    @Published var connected = false
    @Published var status = ""
    @Published var errorMessage: String?
    @Published var hasConflict = false
    @Published var previews: [String:String] = [:]
    @Published var focusEditorToken = UUID()
    let settings = EditorSettings()
    private let backend: any NotesBackend
    private var revision: UInt = 0
    private var editVersion: UInt = 0
    private var savedEditVersion:UInt = 0
    private var lastEdit=Date.distantPast
    private var unsavedSince:Date?
    private var lastAutomaticSave=Date.distantPast
    private var wantsFlush=false
    private let draftWriter=DraftWriter()
    private var lastFolderRefresh=Date.distantPast
    private var composing = false
    private var autosaveTask: Task<Void,Never>?
    private var saveTask: Task<Bool,Never>?
    private var saveGeneration:UInt = 0
    private var draftWork: DispatchWorkItem?
    private var timer: Timer?
    private var polling = false
    private var lastListRefresh = Date.distantPast
    private var previewLoading: Set<String> = []
    private var previewQueue:[String]=[]
    private var previewWorker:Task<Void,Never>?
    private var backupDates: [String:Date] = [:]
    private var retryCount = 0
    private let support: URL
    private let debounce: UInt64?
    private var lastPoll=Date.distantPast
    private var newNoteProfiles:[String:EditingProfile]=[:]
    var dirty:Bool {snapshot != nil && editVersion != savedEditVersion}
    var selectedFolder: NoteFolder? { folders.first { $0.id == selectedFolderID } }
    var visibleNotes:[NoteSummary] {
        let filtered=search.isEmpty ? notes : notes.filter { $0.name.localizedCaseInsensitiveContains(search) || (settings.searchScope=="preview" && (previews[$0.id] ?? "").localizedCaseInsensitiveContains(search)) }
        return filtered.sorted { a,b in
            let order:ComparisonResult
            if settings.sortBy=="title" {order=a.name.localizedStandardCompare(b.name)}
            else {order=(settings.sortBy=="created" ? a.created : a.modified).compare(settings.sortBy=="created" ? b.created : b.modified)}
            if order == .orderedSame {return a.id<b.id}
            return settings.sortAscending ? order == .orderedAscending : order == .orderedDescending
        }
    }
    var editorTitleTemplate:String? { snapshot.flatMap { newNoteProfiles[$0.id]?.titleTemplate ?? $0.profile.titleTemplate } }
    var canSave: Bool { dirty && snapshot?.profile.editable == true && !busy && !hasConflict && !composing }
    var canEdit: Bool { snapshot?.profile.editable == true && !busy && !switching }
    var windowTitle: String { selectedFolder?.name ?? "메모" }

    init(backend: any NotesBackend = NotesService(), supportURL: URL? = nil, startTimer: Bool = true, debounceNanoseconds: UInt64? = nil) {
        self.backend=backend; debounce=debounceNanoseconds
        support=supportURL ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("NotesPlus",isDirectory:true)
        try? FileManager.default.createDirectory(at:support,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        if startTimer {
            timer=Timer.scheduledTimer(withTimeInterval:1,repeats:true) { [weak self] _ in
                Task { @MainActor in
                    guard let self,Date().timeIntervalSince(self.lastPoll)>=self.settings.syncInterval else {return}
                    self.lastPoll=Date(); await self.checkForExternalChanges()
                }
            }
        }
    }
    func connect() async {
        guard !busy else { return }
        busy=true; errorMessage=nil
        do {
            folders=try await backend.folders(); connected=true
            UserDefaults.standard.set(true,forKey:"hasConnected")
            let saved=UserDefaults.standard.string(forKey:"lastFolderID")
            let preferred=folders.first { $0.id==saved } ?? folders.first { $0.account.lowercased().contains("icloud") && $0.name == "Notes" } ?? folders.first
            busy=false
            if let preferred {
                await chooseFolder(preferred.id)
                if settings.restoreLastNote, let last=UserDefaults.standard.string(forKey:"lastNoteID"), notes.contains(where:{$0.id==last}) { await chooseNote(last) }
            }
        } catch { fail(error); busy=false }
    }
    private func prepareToLeave() async -> Bool {
        guard dirty || saving else { return true }
        if await flush() { return true }
        // This is an error/conflict recovery choice, never a routine save prompt.
        persistDraft()
        let alert=NSAlert(); alert.messageText="변경 내용을 아직 동기화하지 못했습니다."
        alert.informativeText="로컬 초안은 보관했습니다. 원본과의 충돌 또는 연결 문제를 해결하려면 이 메모에서 계속 편집하세요."
        alert.addButton(withTitle:"계속 편집"); alert.addButton(withTitle:"초안을 두고 이동")
        return alert.runModal() == .alertSecondButtonReturn
    }
    func chooseFolder(_ id:String) async {
        guard !busy, !switching, selectedFolderID != id else { return }
        switching=true; defer { switching=false }
        guard await prepareToLeave() else { return }
        autosaveTask?.cancel(); revision &+= 1
        busy=true; selectedFolderID=id; selectedNoteID=nil; snapshot=nil; text=""; editorDocument=nil; editorLoadVersion &+= 1; notes=[]; search=""; hasConflict=false; errorMessage=nil
        UserDefaults.standard.set(id,forKey:"lastFolderID")
        do { notes=try await backend.notes(in:id); lastListRefresh=Date(); busy=false }
        catch { fail(error); busy=false }
    }
    func refreshList() async {
        guard let id=selectedFolderID, !busy, !switching else { return }
        do {
            let result=try await backend.notes(in:id)
            if selectedFolderID==id { mergeList(result); lastListRefresh=Date() }
            await checkForExternalChanges()
        } catch { fail(error) }
    }
    func chooseNote(_ id:String) async {
        guard !busy, !switching, selectedNoteID != id else { return }
        switching=true; defer { switching=false }
        guard await prepareToLeave() else { return }
        autosaveTask?.cancel(); revision &+= 1
        busy=true; errorMessage=nil; selectedNoteID=id; snapshot=nil; text=""; editorDocument=nil; editorLoadVersion &+= 1; hasConflict=false
        do {
            install(try await backend.read(id),restoreDraft:true); busy=false
            if dirty && !hasConflict { scheduleAutosave() }
        } catch { fail(error); busy=false }
    }
    private func install(_ note:NoteSnapshot,restoreDraft:Bool) {
        revision &+= 1; editVersion &+= 1; savedEditVersion=editVersion; unsavedSince=nil; composing=false; retryCount=0
        UserDefaults.standard.set(note.id,forKey:"lastNoteID")
        selectedNoteID=note.id; snapshot=note; text=note.document?.text ?? note.text; editorDocument=note.document; editorLoadVersion &+= 1; hasConflict=false; status=""; errorMessage=nil
        previews[note.id]=preview(note.text)
        if restoreDraft, let data=try? Data(contentsOf:draftURL(note.id)), let draft=try? JSONDecoder().decode(LocalDraft.self,from:data), (draft.text != note.text || draft.pendingTitleTemplate != nil) {
            if let title=draft.pendingTitleTemplate {newNoteProfiles[note.id]=EditingProfile(titleTemplate:title)}
            text=draft.text; editorDocument=draft.document ?? NoteDocument(text:draft.text); editVersion &+= 1; unsavedSince=Date(); hasConflict=draft.originalHTML != note.html
            status=hasConflict ? "원본과 다른 초안을 보관 중입니다." : "초안을 복원했습니다."
        }
    }
    func edited(_ value:String,composing isComposing:Bool = false) {
        text=value; composing=isComposing; editVersion &+= 1; lastEdit=Date()
        if unsavedSince==nil {unsavedSince=lastEdit}
        if !status.isEmpty {status=""}
        // Coalesce list previews and draft capture. No list re-sort or disk work on key events.
        if draftWork==nil {
            let item=DispatchWorkItem { [weak self] in
                guard let self else{return}; self.draftWork=nil
                self.updateLivePreview(); self.persistDraft()
            }
            draftWork=item; DispatchQueue.main.asyncAfter(deadline:.now()+1,execute:item)
        }
        if !isComposing {scheduleAutosave()}
    }
    private func updateLivePreview() {
        guard let id=selectedNoteID else{return}
        let title=text.split(separator:"\n",maxSplits:1,omittingEmptySubsequences:false).first.map(String.init) ?? "새로운 메모"
        let body=preview(text)
        if previews[id] != body {previews[id]=body}
        if let i=notes.firstIndex(where:{$0.id==id}),notes[i].name != title {notes[i].name=title}
    }
    private func scheduleAutosave(delay:UInt64? = nil) {
        if let delay {
            autosaveTask?.cancel()
            autosaveTask=Task { [weak self] in
                do {try await Task.sleep(nanoseconds:delay)} catch{return}
                guard let self,!Task.isCancelled else{return}
                self.autosaveTask=nil; _ = await self.save()
            }
            return
        }
        guard autosaveTask==nil else{return}
        autosaveTask=Task { [weak self] in
            while let self,!Task.isCancelled {
                let idle=Double(self.debounce ?? UInt64(self.settings.autosaveDelay*1_000_000_000))/1_000_000_000
                let waitForIdle=max(0,idle-Date().timeIntervalSince(self.lastEdit))
                let waitForBatch=max(0,self.settings.autosaveMaxInterval-Date().timeIntervalSince(self.unsavedSince ?? Date()))
                let throttle=self.debounce == nil ? max(0,1.5-Date().timeIntervalSince(self.lastAutomaticSave)) : 0
                let wait=max(throttle,min(waitForIdle,waitForBatch))
                if wait>0 {do {try await Task.sleep(nanoseconds:UInt64(max(0.01,wait)*1_000_000_000))} catch{return}; continue}
                self.autosaveTask=nil
                guard !self.composing else{return}
                self.lastAutomaticSave=Date(); _ = await self.save(); return
            }
        }
    }
    @discardableResult func flush() async -> Bool {
        autosaveTask?.cancel(); autosaveTask=nil; wantsFlush=true
        var result=await save()
        // Another caller may have observed the just-completed automatic batch.
        if dirty,canSave,errorMessage==nil {result=await save()}
        wantsFlush=false
        await draftWriter.barrier()
        return result && !dirty
    }
    // One writer drains every committed edit. Editing stays enabled while a write is in flight.
    @discardableResult func save() async -> Bool {
        if let task=saveTask {
            let generation=saveGeneration
            let result=await task.value
            if saveGeneration==generation {saveTask=nil}
            return result && !dirty
        }
        guard dirty else { return true }
        guard canSave else { persistDraft(); return false }
        saveGeneration &+= 1; let generation=saveGeneration
        let task=Task { [weak self] () -> Bool in
            guard let self else { return false }
            return await self.drainSaves()
        }
        saveTask=task
        let result=await task.value
        if saveGeneration==generation {saveTask=nil}
        // An edit can arrive while another caller is awaiting completion of this task.
        if dirty,!composing,!hasConflict,errorMessage==nil {scheduleAutosave()}
        return result && !dirty
    }
    private func drainSaves() async -> Bool {
        saving=true; defer { saving=false }
        while dirty {
            guard !composing, !hasConflict, let original=snapshot, original.profile.editable else { persistDraft(); return false }
            let submittedDocument=currentDocument()
            let submitted=submittedDocument.text
            let submittedVersion=editVersion
            let profile=newNoteProfiles[original.id] ?? original.profile
            if original.document?.equivalent(to:submittedDocument)==true,newNoteProfiles[original.id]==nil {
                savedEditVersion=submittedVersion; unsavedSince=nil; persistDraft(); continue
            }
            let html=await Task.detached(priority:.utility) {NoteCodec.html(for:submittedDocument,profile:profile)}.value
            persistDraft()
            do {
                try await backup(original)
                let saved=try await writePreservingCanonicalChanges(original,html:html)
                guard let savedDocument=saved.document,savedDocument.equivalent(to:submittedDocument) else {
                    hasConflict=true
                    throw NSError(domain:"NotesPlus",code:422,userInfo:[NSLocalizedDescriptionKey:"저장 후 원본이 예상과 다릅니다. 로컬 초안을 보관했습니다."])
                }
                guard selectedNoteID==original.id else { return false }
                // Use the canonical HTML as the next comparison base without replacing newer
                // keystrokes, the caret, marked text or the text view's undo history.
                newNoteProfiles[original.id]=nil
                var baseline=saved; baseline.text=submitted; baseline.document=submittedDocument; snapshot=baseline; revision &+= 1
                savedEditVersion=submittedVersion; unsavedSince=dirty ? Date() : nil
                if let i=notes.firstIndex(where:{$0.id==saved.id}) {
                    notes[i].modified=saved.modified
                    if editVersion==submittedVersion { notes[i].name=saved.name }
                }
                notes.sort { $0.modified > $1.modified }
                retryCount=0; errorMessage=nil; status="자동 저장됨"
                persistDraft()
                if !wantsFlush {break}
            } catch {
                if (error as NSError).code==409 { hasConflict=true }
                fail(error); persistDraft()
                if !hasConflict, retryCount<3 {
                    retryCount += 1
                    scheduleAutosave(delay:UInt64(retryCount)*2_000_000_000)
                }
                return false
            }
        }
        return true
    }
    private func sameContent(_ a:NoteSnapshot,_ b:NoteSnapshot)->Bool {
        ((a.document != nil && b.document != nil) ? a.document!.equivalent(to:b.document!) : NoteCodec.normalized(a.text)==NoteCodec.normalized(b.text)) &&
            a.profile.reason==b.profile.reason && a.profile.titleTemplate==b.profile.titleTemplate
    }
    private func writePreservingCanonicalChanges(_ original:NoteSnapshot,html:String) async throws -> NoteSnapshot {
        do { return try await backend.write(original.id,expectedHTML:original.html,html:html) }
        catch {
            guard (error as NSError).code==409 else { throw error }
            let fresh=try await backend.read(original.id)
            guard sameContent(original,fresh), fresh.profile.editable else { throw error }
            // Retry once only when Notes changed its serialization, not the note's content.
            return try await backend.write(original.id,expectedHTML:fresh.html,html:html)
        }
    }
    private func draftURL(_ id:String)->URL {
        let name=SHA256.hash(data:Data(id.utf8)).map { String(format:"%02x",$0) }.joined()
        return support.appendingPathComponent("draft-\(name).json")
    }
    private func currentDocument()->NoteDocument {
        if editorBridge.noteID==selectedNoteID,let capture=editorBridge.capture {return capture()}
        if let document=editorDocument,document.text==text {return document}
        return NoteDocument(text:text)
    }
    func persistDraft() {
        guard let s=snapshot else{return}
        let draft:LocalDraft? = dirty || newNoteProfiles[s.id] != nil ? LocalDraft(id:s.id,originalHTML:s.html,text:text,modified:Date(),pendingTitleTemplate:newNoteProfiles[s.id]?.titleTemplate,document:currentDocument()) : nil
        draftWriter.submit(draft,to:draftURL(s.id)) { [weak self] error in
            Task { @MainActor in self?.errorMessage="로컬 초안을 저장하지 못했습니다: \(error.localizedDescription)" }
        }
    }
    private func backup(_ note:NoteSnapshot) async throws {
        if let date=backupDates[note.id],Date().timeIntervalSince(date)<300 {return}
        let directory=support.appendingPathComponent("Backups",isDirectory:true)
        let draft=LocalDraft(id:note.id,originalHTML:note.html,text:note.text,modified:Date(),document:note.document)
        try await draftWriter.backup(draft,to:directory.appendingPathComponent("\(UUID().uuidString).json"))
        backupDates[note.id]=Date()
    }
    func newNote() async {
        guard !busy, !switching else {return}
        let folder=settings.defaultFolderID.isEmpty ? selectedFolder : folders.first{$0.id==settings.defaultFolderID}
        guard let folder,!folder.shared,folder.name != "Recently Deleted" else {
            errorMessage="새 메모를 만들 수 있는 폴더를 설정에서 선택해 주세요."; return
        }
        switching=true; defer { switching=false }
        guard await prepareToLeave() else { return }
        autosaveTask?.cancel(); busy=true
        do {
            let profile=settings.newNoteProfile
            let note=try await backend.create(in:folder.id,html:NoteCodec.html(for:"",profile:profile))
            // Notes can discard the heading of an empty note. Keep it until first content save.
            if profile.titleTemplate != nil {newNoteProfiles[note.id]=profile}
            if selectedFolderID != folder.id {
                selectedFolderID=folder.id; search=""
                UserDefaults.standard.set(folder.id,forKey:"lastFolderID")
                notes=try await backend.notes(in:folder.id)
            }
            install(note,restoreDraft:false)
            notes.removeAll{$0.id==note.id}
            notes.insert(NoteSummary(["id":note.id,"name":note.name,"modified":note.modified,"created":note.created]),at:0)
            busy=false; focusEditorToken=UUID(); persistDraft()
        } catch { fail(error); busy=false }
    }
    func openOriginal() async {
        guard let id=selectedNoteID else { return }
        _ = await flush()
        do { try await backend.show(id) } catch { fail(error) }
    }
    func reloadOriginal() async {
        guard let id=selectedNoteID, !busy, !saving else { return }
        persistDraft(); autosaveTask?.cancel()
        let alert=NSAlert(); alert.messageText="기본 메모의 현재 내용을 불러올까요?"
        alert.informativeText="현재 초안을 따로 보관한 뒤 원본을 불러옵니다."
        alert.addButton(withTitle:"불러오기"); alert.addButton(withTitle:"취소")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        busy=true
        do {
            await draftWriter.barrier()
            let fresh=try await backend.read(id)
            let draft=draftURL(id)
            if FileManager.default.fileExists(atPath:draft.path) {
                try FileManager.default.moveItem(at:draft,to:support.appendingPathComponent("recovered-\(UUID().uuidString).json"))
            }
            newNoteProfiles[id]=nil; install(fresh,restoreDraft:false); busy=false
        } catch { fail(error); busy=false }
    }
    func checkForExternalChanges() async {
        guard connected, !busy, !saving, !switching, !polling else { return }
        polling=true; defer { polling=false }
        let token=revision
        do {
            if let old=snapshot {
                let fresh=try await backend.read(old.id)
                guard token==revision, snapshot?.id==old.id, snapshot?.html==old.html, !busy, !saving, !switching else { return }
                if fresh.html != old.html {
                    if sameContent(fresh,old) {
                        // Notes may normalize its HTML asynchronously after a successful save.
                        // Refresh only the comparison baseline; preserve caret/undo/local typing.
                        var baseline=fresh; baseline.text=old.text; baseline.document=old.document; snapshot=baseline; revision &+= 1
                        if dirty { persistDraft() }
                    }
                    else if dirty { hasConflict=true; autosaveTask?.cancel(); status="다른 기기에서 원본이 변경되었습니다."; persistDraft() }
                    else { install(fresh,restoreDraft:false) }
                }
            }
            if Date().timeIntervalSince(lastListRefresh)>=settings.syncInterval,let id=selectedFolderID {
                let result=try await backend.notes(in:id)
                guard selectedFolderID==id,!busy,!switching else{return}
                let oldDates=Dictionary(uniqueKeysWithValues:notes.map { ($0.id,$0.modified) })
                for note in result where oldDates[note.id] != note.modified { previews[note.id]=nil }
                mergeList(result); lastListRefresh=Date()
            }
            if Date().timeIntervalSince(lastFolderRefresh)>30,!dirty {
                let fresh=try await backend.folders()
                if folders != fresh {folders=fresh}; lastFolderRefresh=Date()
            }
        } catch {if status != "원본 변경 확인 대기 중" {status="원본 변경 확인 대기 중"}}
    }
    private func mergeList(_ incoming:[NoteSummary]) {
        var result=incoming
        if dirty,let current=notes.first(where:{$0.id==selectedNoteID}),let i=result.firstIndex(where:{$0.id==current.id}) {result[i].name=current.name}
        if notes != result {notes=result}
    }
    func loadPreview(_ id:String) async {
        guard previews[id]==nil,!previewLoading.contains(id),!previewQueue.contains(id) else{return}
        previewQueue.append(id)
        guard previewWorker==nil else{return}
        previewWorker=Task { [weak self] in
            guard let self else{return}
            defer {self.previewWorker=nil}
            while !self.previewQueue.isEmpty,!Task.isCancelled {
                if self.saving || self.dirty || self.busy || self.switching {
                    try? await Task.sleep(nanoseconds:500_000_000); continue
                }
                let next=self.previewQueue.removeFirst()
                guard self.notes.contains(where:{$0.id==next}),self.previews[next]==nil else{continue}
                self.previewLoading.insert(next)
                let note=try? await self.backend.read(next)
                self.previewLoading.remove(next)
                if let note,self.notes.contains(where:{$0.id==next}) {
                    if self.selectedNoteID==next,self.dirty {continue}
                    self.previews[next]=note.profile.reason?.hasPrefix("잠긴")==true ? "잠긴 메모" : self.preview(note.text)
                }
            }
        }
    }
    private func preview(_ value:String)->String {
        let lines=value.split(separator:"\n",maxSplits:4,omittingEmptySubsequences:false).dropFirst().prefix(3).filter{!$0.trimmingCharacters(in:.whitespaces).isEmpty}
        return lines.isEmpty ? "추가 텍스트 없음" : lines.joined(separator:" ")
    }
    func openSupportFolder() { NSWorkspace.shared.open(support) }
    func retry() async { retryCount=0; _ = await flush() }
    private func fail(_ error:Error) {
        let e=error as NSError
        errorMessage=e.code == -1743 ? "시스템 설정 → 개인정보 보호 및 보안 → 자동화에서 메모 접근을 허용해 주세요." : e.localizedDescription
        status="자동 저장 대기 중"
    }
}
