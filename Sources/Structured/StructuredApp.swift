import AppKit
import SwiftUI

private struct StructuredDraft:Codable {var base:CloudSnapshot;var document:CloudDocument}
private struct StructuredHistory:Codable {var latest:CloudSnapshot;var superseded:[String]}
@MainActor final class StructuredModel:ObservableObject {
    @Published var notes:[CloudSummary]=[]
    @Published var snapshot:CloudSnapshot?
    @Published var document=CloudDocument(paragraphs:[CloudParagraph()])
    @Published var status="iCloud 연결이 필요합니다."
    @Published var connected=false
    @Published var loading=false
    @Published var dirty=false
    @Published var saving=false
    @Published var revision=0
    @Published var fontSize=17.0
    @Published var lineRatio=1.6
    let editor=StructuredEditorHandle()
    let client:any CloudRequesting
    private var account:CloudAccount?
    private var login:CloudLogin?
    private var debounce:Task<Void,Never>?,journal:Task<Void,Never>?,poll:Task<Void,Never>?
    private var generation=0,lastSaved=Date.distantPast
    private var supersededVersions:[String:[String]]=[:]
    private var fixture=false
    private let support:URL
    init(client:any CloudRequesting=CloudClient(),account:CloudAccount?=nil,startTasks:Bool=true,support:URL?=nil) {
        self.client=client;self.account=account;self.connected=account != nil
        self.support=support ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("NotesPlus Experimental",isDirectory:true)
        fontSize=UserDefaults.standard.object(forKey:"structuredFontSize") as? Double ?? 17
        lineRatio=UserDefaults.standard.object(forKey:"structuredLineRatio") as? Double ?? 1.6
        try? FileManager.default.createDirectory(at:self.support,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        if ProcessInfo.processInfo.arguments.contains("--fixture") {
            fixture=true;connected=true
            var check=CloudParagraph(text:"체크하면 상태가 바뀝니다",kind:"todoList");check.done=false
            var table=CloudParagraph(text:"\u{fffc}");table.tableID="fixture-table"
            document=CloudDocument(paragraphs:[CloudParagraph(text:"NotesPlus 편집 실험",kind:"title"),CloudParagraph(text:"한글 입력과 서식을 확인합니다."),CloudParagraph(text:"글머리 항목",kind:"bulletList"),check,table,CloudParagraph(text:"표 아래 본문")],tables:[CloudTable(id:"fixture-table",grid:[["항목","내용"],["표 셀","여기서 바로 편집"]])])
            snapshot=CloudSnapshot(id:"fixture",title:"NotesPlus 편집 실험",tag:"fixture",document:document,created:0);notes=[CloudSummary(id:"fixture",title:"NotesPlus 편집 실험",created:0)];status="로컬 편집 검증 · iCloud에 저장하지 않음";return
        }
        guard startTasks else{return}
        Task {
            let restored=await Task.detached(priority:.userInitiated){CloudKeychain.load()}.value
            if self.account==nil {self.account=restored}
            connected=self.account != nil
            if connected {await reloadList()}
        }
        poll=Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for:.seconds(4));guard !Task.isCancelled,let self else{return}
                if self.dirty,Date().timeIntervalSince(self.lastSaved)>8 {await self.save()}
                else if !self.dirty {await self.refresh()}
            }
        }
    }
    func signIn() {
        if login==nil {
            login=CloudLogin(client:client)
            login?.onAccount={ [weak self] account in guard let self else{return};self.account=account;self.connected=true;Task {await self.reloadList()}}
        }
        login?.show()
    }
    func reloadList() async {
        guard let account,!fixture else{return};loading=true;status="iCloud 메모를 불러오는 중…";defer{loading=false}
        do {
            let listing=try await client.request("list",account:account,as:CloudListing.self);notes=listing.notes
            status=notes.isEmpty ? "새 메모를 만들면 iCloud의 ‘NotesPlus 실험’ 폴더에 저장됩니다.":"iCloud 연결됨"
            if snapshot==nil,let first=notes.first {await select(first.id)}
        }catch{status=error.localizedDescription}
    }
    func select(_ id:String) async {
        guard id != snapshot?.id,let account,!fixture else{return}
        persistDraft();debounce?.cancel();loading=true;defer{loading=false}
        do {
            let remote=try await client.request("read",account:account,payload:["id":id],as:CloudSnapshot.self)
            let history=(try? Data(contentsOf:historyURL(id))).flatMap{try? JSONDecoder().decode(StructuredHistory.self,from:$0)}
            if let history {supersededVersions[id]=history.superseded}
            let current=(history?.superseded.contains(remote.tag)==true) ? history!.latest:remote
            if let data=try? Data(contentsOf:draftURL(id)),let draft=try? JSONDecoder().decode(StructuredDraft.self,from:data) {
                snapshot=draft.base;document=draft.document;dirty=true;status="이전 입력을 복원했습니다. 저장 시 최신 iCloud 내용과 합칩니다."
            }else{snapshot=current;document=current.document;dirty=false;status="iCloud 동기화됨"}
            generation+=1;revision+=1
        }catch{status=error.localizedDescription}
    }
    func create() async {
        guard let account,!fixture else{return};persistDraft();loading=true;defer{loading=false}
        do {
            let note=try await client.request("create",account:account,as:CloudSnapshot.self)
            snapshot=note;document=note.document;dirty=false;generation+=1;revision+=1
            notes.insert(CloudSummary(id:note.id,title:note.title,created:note.created),at:0);status="새 메모 · 자동 저장"
        }catch{status=error.localizedDescription}
    }
    func edited(_ document:CloudDocument) {
        self.document=document;generation+=1;dirty=true;status=fixture ? "로컬 변경됨 · iCloud에 저장하지 않음":"입력 중 · 초안 보관"
        journal?.cancel();journal=Task {try? await Task.sleep(for:.milliseconds(250));guard !Task.isCancelled else{return};persistDraft()}
        debounce?.cancel();debounce=Task {try? await Task.sleep(for:.milliseconds(1200));guard !Task.isCancelled else{return};await save()}
    }
    func save() async {
        guard dirty,!saving,!fixture,let base=snapshot,let account else{return}
        persistDraft();saving=true;let sent=document,version=generation;status="iCloud에 저장 중…"
        defer{saving=false}
        do {
            let payload:[String:Any]=["id":base.id,"base":try object(base.document),"document":try object(sent)]
            var saved=try await client.request("save",account:account,payload:payload,as:CloudSnapshot.self)
            guard snapshot?.id==base.id else{return}
            rememberOldVersion(base)
            persistHistory(saved)
            if version==generation {
                if document != saved.document {document=saved.document;revision+=1}
                snapshot=saved;dirty=false;try? FileManager.default.removeItem(at:draftURL(base.id));status="iCloud 동기화됨"
            }else {
                // Rebase the next local edit against what this save actually submitted.
                // A merged remote paragraph must not become a local deletion on the next save.
                saved.document=sent;snapshot=saved;persistDraft();status="입력 중 · 이전 변경 저장됨"
            }
            lastSaved=Date()
            if let i=notes.firstIndex(where:{$0.id==base.id}) {notes[i].title=saved.title}
        }catch{status=error.localizedDescription;persistDraft()}
    }
    func refresh() async {
        guard !dirty,!saving,!loading,!fixture,let base=snapshot,let account,editor.view?.hasMarkedText() != true else{return}
        let version=generation
        do {
            let remote=try await client.request("read",account:account,payload:["id":base.id],as:CloudSnapshot.self)
            guard snapshot?.id==base.id,generation==version,!dirty,editor.view?.hasMarkedText() != true else{return}
            guard !(supersededVersions[base.id] ?? []).contains(remote.tag) else{return}
            if remote.tag != base.tag || remote.document != document {
                if remote.tag != base.tag {rememberOldVersion(base)}
                snapshot=remote
                persistHistory(remote)
                if document != remote.document {document=remote.document;revision+=1}
                status="다른 기기의 변경을 불러왔습니다. 계속 편집할 수 있습니다."
            }
        }catch{status="연결 대기 · 입력은 계속할 수 있습니다."}
    }
    @discardableResult func persistDraft()->Bool {
        guard dirty,let snapshot,!fixture else{return true}
        do {
            let data=try JSONEncoder().encode(StructuredDraft(base:snapshot,document:document))
            try data.write(to:draftURL(snapshot.id),options:.atomic)
            try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:draftURL(snapshot.id).path)
            return true
        }catch{status="초안을 디스크에 보관하지 못했습니다: \(error.localizedDescription)";return false}
    }
    func savePreferences() {UserDefaults.standard.set(fontSize,forKey:"structuredFontSize");UserDefaults.standard.set(lineRatio,forKey:"structuredLineRatio")}
    private func rememberOldVersion(_ snapshot:CloudSnapshot) {
        var versions=supersededVersions[snapshot.id] ?? []
        if !versions.contains(snapshot.tag) {versions.append(snapshot.tag)}
        supersededVersions[snapshot.id]=Array(versions.suffix(24))
    }
    private func persistHistory(_ snapshot:CloudSnapshot) {
        let history=StructuredHistory(latest:snapshot,superseded:supersededVersions[snapshot.id] ?? [])
        if let data=try? JSONEncoder().encode(history) {try? data.write(to:historyURL(snapshot.id),options:.atomic);try? FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:historyURL(snapshot.id).path)}
    }
    private func historyURL(_ id:String)->URL {support.appendingPathComponent("history-"+id.filter{$0.isLetter || $0.isNumber || $0=="-"}+".json")}
    private func draftURL(_ id:String)->URL {support.appendingPathComponent(id.filter{$0.isLetter || $0.isNumber || $0=="-"}+".json")}
    private func object<T:Encodable>(_ value:T)throws->Any {try JSONSerialization.jsonObject(with:JSONEncoder().encode(value))}
}

struct StructuredWindow:View {
    @ObservedObject var model:StructuredModel
    var body:some View {
        NavigationSplitView {
            List {Label("iCloud",systemImage:"icloud");Label("NotesPlus 실험",systemImage:"folder")}.navigationSplitViewColumnWidth(min:150,ideal:175,max:220)
        } content: {
            List(model.notes) {note in
                Button {Task{await model.select(note.id)}} label: {VStack(alignment:.leading,spacing:6){Text(note.title.isEmpty ? "새로운 메모":note.title).font(.headline).lineLimit(2);Text("iCloud").font(.caption).foregroundStyle(.secondary)}.frame(maxWidth:.infinity,alignment:.leading).padding(.vertical,7)}.buttonStyle(.plain)
            }.navigationSplitViewColumnWidth(min:200,ideal:250,max:350)
        } detail: {
            VStack(spacing:0) {
                if let note=model.snapshot {
                    StructuredEditor(document:model.document,identity:note.id,revision:model.revision,size:model.fontSize,ratio:model.lineRatio,handle:model.editor,onChange:model.edited)
                }else {
                    ContentUnavailableView {Label("NotesPlus",systemImage:"note.text")} description: {Text(model.connected ? "새 메모를 만들어 편집을 시작하세요.":"체크리스트와 표를 보존하려면 iCloud에 연결하세요.")} actions: {Button(model.connected ? "새 메모":"iCloud 연결"){if model.connected {Task{await model.create()}}else{model.signIn()}}}
                }
                Divider()
                HStack {if model.saving {ProgressView().controlSize(.small)};Text(model.status).font(.caption).foregroundStyle(.secondary).textSelection(.enabled);Spacer()}.padding(9)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button {Task{await model.create()}} label:{Image(systemName:"square.and.pencil")}.help("새 메모").disabled(!model.connected || model.loading)
                Menu {Button("본문"){model.editor.format("body")};Button("제목"){model.editor.format("title")};Button("소제목"){model.editor.format("heading")};Divider();Button("굵게"){model.editor.inline("bold")};Button("기울임"){model.editor.inline("italic")};Button("밑줄"){model.editor.inline("underline")}} label:{Image(systemName:"textformat")}
                Menu {Button("글머리 기호"){model.editor.format("bulletList")};Button("번호 목록"){model.editor.format("numberedList")};Button("대시 목록"){model.editor.format("dashList")};Button("목록 해제"){model.editor.format("body")}} label:{Image(systemName:"list.bullet")}
                Button {model.editor.format("todoList")} label:{Image(systemName:"checklist")}.help("체크리스트")
                Button {Task{await model.save();await model.refresh()}} label:{Image(systemName:"arrow.triangle.2.circlepath")}.help("동기화")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for:NSApplication.didBecomeActiveNotification)) {_ in Task {await model.refresh()}}
        .onReceive(NotificationCenter.default.publisher(for:NSApplication.willResignActiveNotification)) {_ in model.persistDraft();Task{await model.save()}}
        .frame(minWidth:850,minHeight:520)
    }
}
final class StructuredAppDelegate:NSObject,NSApplicationDelegate {
    var model:StructuredModel?
    func applicationShouldTerminate(_ sender:NSApplication)->NSApplication.TerminateReply {
        MainActor.assumeIsolated {
            if let view=model?.editor.view,view.hasMarkedText() {view.unmarkText();model?.edited(StructuredCodec.capture(view))}
            return model?.persistDraft()==false ? .terminateCancel:.terminateNow
        }
    }
}
#if !STRUCTURED_MODEL_TESTS
@main
#endif
struct StructuredApp:App {
    @NSApplicationDelegateAdaptor(StructuredAppDelegate.self) var delegate
    @StateObject var model=StructuredModel()
    var body:some Scene {
        WindowGroup("NotesPlus Experimental") {StructuredWindow(model:model).onAppear{delegate.model=model}}
        .commands {
            CommandGroup(after:.appInfo) {Button("iCloud 연결…"){model.signIn()}}
            CommandGroup(replacing:.newItem) {Button("새 메모"){Task{await model.create()}}.keyboardShortcut("n")}
            CommandGroup(replacing:.textFormatting) {Button("굵게"){model.editor.inline("bold")}.keyboardShortcut("b");Button("기울임"){model.editor.inline("italic")}.keyboardShortcut("i");Button("밑줄"){model.editor.inline("underline")}.keyboardShortcut("u")}
            CommandGroup(after:.textFormatting) {Button("글머리 기호"){model.editor.format("bulletList")};Button("번호 목록"){model.editor.format("numberedList")};Button("체크리스트"){model.editor.format("todoList")}.keyboardShortcut("l",modifiers:[.command,.shift])}
        }
        Settings {
            Form {
                LabeledContent("글자 크기"){Slider(value:$model.fontSize,in:12...28,step:1);Text("\(Int(model.fontSize))")}
                LabeledContent("행간"){Slider(value:$model.lineRatio,in:1...2.2,step:0.05);Text(model.lineRatio,format:.number.precision(.fractionLength(2)))}
                Text("NotesPlus Experimental · 구조 보존 연결 검증용").font(.caption).foregroundStyle(.secondary)
                Button("iCloud 연결…"){model.signIn()}
            }.padding(24).frame(width:430).onChange(of:model.fontSize){model.savePreferences()}.onChange(of:model.lineRatio){model.savePreferences()}
        }
    }
}
