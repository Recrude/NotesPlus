import SwiftUI
import AppKit

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: NotesModel?
    private var closingObserver: NSObjectProtocol?
    private var finishing = false
    func applicationDidFinishLaunching(_ notification:Notification) {
        if let path=Bundle.main.path(forResource:"AppIcon",ofType:"icns"), let icon=NSImage(contentsOfFile:path) {
            NSApplication.shared.applicationIconImage=icon
        }
        closingObserver=NotificationCenter.default.addObserver(forName:NSWindow.willCloseNotification,object:nil,queue:.main) { [weak self] _ in
            Task { @MainActor in self?.model?.persistDraft(); _ = await self?.model?.flush() }
        }
    }
    func applicationDidBecomeActive(_ notification:Notification) {
        Task { await model?.refreshList() }
    }
    func applicationWillResignActive(_ notification:Notification) {
        model?.persistDraft()
        Task { _ = await model?.flush() }
    }
    func applicationShouldTerminate(_ sender:NSApplication)->NSApplication.TerminateReply {
        guard let model, model.dirty || model.saving else { return .terminateNow }
        guard !finishing else { return .terminateLater }
        finishing=true
        sender.keyWindow?.makeFirstResponder(nil)
        model.persistDraft()
        Task {
            let saved=await model.flush()
            if saved { sender.reply(toApplicationShouldTerminate:true) }
            else {
                let alert=NSAlert(); alert.messageText="동기화하지 못한 변경 사항이 있습니다."
                alert.informativeText="로컬 초안은 보관되어 있으며 다음 실행 때 복원됩니다."
                alert.addButton(withTitle:"계속 사용"); alert.addButton(withTitle:"초안을 보관하고 종료")
                let quit=alert.runModal() == .alertSecondButtonReturn
                finishing=false; sender.reply(toApplicationShouldTerminate:quit)
            }
        }
        return .terminateLater
    }
    func applicationWillTerminate(_ notification:Notification) { model?.persistDraft() }
}

@main struct NotesPlusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model=NotesModel()
    var body: some Scene {
        Window("NotesPlus",id:"main") {
            MainView(model:model)
                .onAppear { delegate.model=model }
                .task { if UserDefaults.standard.bool(forKey:"hasConnected"), !model.connected { await model.connect() } }
                .frame(minWidth:860,minHeight:560)
                .tint(Color(red:0,green:122.0/255,blue:1))
        }
        .defaultSize(width:1080,height:740)
        .commands {
            CommandGroup(replacing:.newItem) {
                Button("새로운 메모") { Task { await model.newNote() } }.keyboardShortcut("n").disabled(!model.connected || model.busy)
            }
            CommandGroup(replacing:.saveItem) { }
            TimestampCommands(settings:model.settings)
            CommandMenu("메모") {
                Button("기본 메모에서 열기") { Task { await model.openOriginal() } }.disabled(model.selectedNoteID == nil)
                Divider()
                Button("다시 동기화") { Task { _ = await model.flush(); await model.refreshList() } }.keyboardShortcut("r").disabled(!model.connected)
            }
        }
        Settings { SettingsView(settings:model.settings,model:model) }
    }
}

struct TimestampCommands:Commands {
    @ObservedObject var settings:EditorSettings
    var body:some Commands {
        CommandGroup(after:.pasteboard) {
            Divider()
            Button("타임스탬프 삽입") {
                NSApp.sendAction(#selector(PlainNoteTextView.insertTimestamp(_:)),to:nil,from:nil)
            }
            .keyboardShortcut(KeyEquivalent(settings.timestampKey.first ?? "t"),modifiers:TimestampShortcut.modifiers(settings.timestampModifiers))
        }
    }
}

struct NoteGroup: Identifiable { let id:String; var notes:[NoteSummary] }
struct MainView: View {
    @ObservedObject var model:NotesModel
    @State private var visibility=NavigationSplitViewVisibility.all
    @ObservedObject var settings:EditorSettings
    init(model:NotesModel) {self.model=model; self.settings=model.settings}
    var accounts:[String] { Array(Set(model.folders.map(\.account))).sorted { a,b in a.lowercased().contains("icloud") ? true : (b.lowercased().contains("icloud") ? false : a<b) } }
    var groups:[NoteGroup] {
        var result:[NoteGroup]=[]
        for note in model.visibleNotes {
            let key=settings.groupByDate && settings.sortBy != "title" ? dateGroup(settings.sortBy=="created" ? note.created : note.modified) : ""
            if let i=result.firstIndex(where:{$0.id==key}) { result[i].notes.append(note) }
            else { result.append(NoteGroup(id:key,notes:[note])) }
        }
        return result
    }
    private func dateGroup(_ date:Date)->String {
        let c=Calendar.current
        if c.isDateInToday(date) { return "오늘" }
        if c.isDateInYesterday(date) { return "어제" }
        let days=c.dateComponents([.day],from:c.startOfDay(for:date),to:c.startOfDay(for:Date())).day ?? 0
        if days<7 { return "이전 7일" }; if days<30 { return "이전 30일" }
        return date.formatted(.dateTime.year().month(.wide))
    }
    var body: some View {
        Group {
            if model.connected {
                NavigationSplitView(columnVisibility:$visibility) {
                    List(selection:Binding(get:{model.selectedFolderID},set:{ id in if let id { Task { await model.chooseFolder(id) } } })) {
                        ForEach(accounts,id:\.self) { account in
                            Section(account) {
                                ForEach(model.folders.filter{$0.account==account}) { folder in
                                    HStack {
                                        Image(systemName:folder.name == "Recently Deleted" ? "trash" : (folder.shared ? "folder.badge.person.crop" : "folder"))
                                        Text(folder.name)
                                        Spacer(minLength:4)
                                        if settings.showFolderCounts { Text("\(folder.id==model.selectedFolderID ? model.notes.count : folder.count)").foregroundStyle(.secondary).monospacedDigit() }
                                    }.padding(.leading,CGFloat(folder.depth)*12).tag(folder.id)
                                }
                            }
                        }
                    }
                    .listStyle(.sidebar)
                    .navigationSplitViewColumnWidth(min:170,ideal:210,max:280)
                } content: {
                    Group {
                        if settings.galleryView {
                            ScrollView {
                                LazyVGrid(columns:[GridItem(.adaptive(minimum:180))],spacing:14) {
                                    ForEach(model.visibleNotes) { note in
                                        Button { Task { await model.chooseNote(note.id) } } label:{ noteRow(note).frame(maxWidth:.infinity,alignment:.leading).padding(15).background(.background,in:RoundedRectangle(cornerRadius:10)).overlay(RoundedRectangle(cornerRadius:10).stroke(model.selectedNoteID==note.id ? Color.accentColor : Color.secondary.opacity(0.2),lineWidth:model.selectedNoteID==note.id ? 2 : 1)) }
                                            .buttonStyle(.plain)
                                    }
                                }.padding(14)
                            }
                        } else {
                            List(selection:Binding(get:{model.selectedNoteID},set:{ id in if let id { Task { await model.chooseNote(id) } } })) {
                                ForEach(groups) { group in
                                    Section {
                                        ForEach(group.notes) { note in noteRow(note).tag(note.id) }
                                    } header:{ if !group.id.isEmpty { Text(group.id).font(.system(size:14,weight:.semibold)).foregroundStyle(.primary).padding(.top,10) } }
                                }
                            }.listStyle(.inset)
                        }
                    }
                    .navigationTitle(model.windowTitle)
                    .navigationSubtitle("\(model.notes.count)개의 메모")
                    .navigationSplitViewColumnWidth(min:200,ideal:250,max:420)
                    .toolbar {
                        ToolbarItem {
                            Menu {
                                Picker("보기",selection:$settings.values.galleryView) { Text("목록").tag(false); Text("갤러리").tag(true) }
                                Picker("정렬",selection:$settings.values.sortBy) { Text("수정일").tag("modified"); Text("생성일").tag("created"); Text("제목").tag("title") }
                                Toggle("날짜별로 그룹화",isOn:$settings.values.groupByDate).disabled(settings.sortBy=="title")
                            } label:{ Image(systemName:"ellipsis") }
                            .menuIndicator(.hidden).help("메모 보기 옵션")
                        }
                    }
                } detail: {
                    editor
                        .toolbar {
                            ToolbarItem(placement:.primaryAction) {
                                Button { Task { await model.newNote() } } label:{ Image(systemName:"square.and.pencil") }
                                    .help("새로운 메모 (⌘N)").disabled(model.busy || model.selectedFolder?.shared == true)
                            }
                            ToolbarItemGroup(placement:.primaryAction) {
                                if settings.showFormatTool { Menu {
                                    Button("기본 메모에서 서식 편집…") { Task { await model.openOriginal() } }
                                } label:{ Image(systemName:"textformat") }.menuIndicator(.hidden).help("서식").disabled(model.selectedNoteID == nil) }
                                if settings.showChecklistTool { Button { Task { await model.openOriginal() } } label:{ Image(systemName:"checklist") }.help("기본 메모에서 체크리스트 편집").disabled(model.selectedNoteID == nil) }
                                if settings.showTableTool { Button { Task { await model.openOriginal() } } label:{ Image(systemName:"tablecells") }.help("기본 메모에서 표 편집").disabled(model.selectedNoteID == nil) }
                                if settings.showAttachmentTool { Button { Task { await model.openOriginal() } } label:{ Image(systemName:"paperclip") }.help("기본 메모에서 첨부파일 편집").disabled(model.selectedNoteID == nil) }
                                if settings.showShareTool { ShareLink(item:model.text) { Image(systemName:"square.and.arrow.up") }.help("텍스트 사본 공유").disabled(model.selectedNoteID == nil) }
                                Menu {
                                    Button("기본 메모에서 열기") { Task { await model.openOriginal() } }
                                    Divider()
                                    SettingsLink { Text("NotesPlus 설정…") }
                                } label:{ Image(systemName:"ellipsis") }.menuIndicator(.hidden).help("더 보기")
                            }
                        }
                }
                .navigationSplitViewStyle(.balanced)
                .searchable(text:$model.search,placement:.toolbar,prompt:settings.searchScope=="title" ? "제목 검색" : "제목 및 미리보기 검색")
            } else {
                VStack(spacing:15) {
                    if let icon=NSImage(named:NSImage.applicationIconName) { Image(nsImage:icon).resizable().frame(width:76,height:76) }
                    Text("NotesPlus").font(.title2.weight(.semibold))
                    Button("메모 연결") { Task { await model.connect() } }.buttonStyle(.borderedProminent).disabled(model.busy)
                }.frame(maxWidth:.infinity,maxHeight:.infinity)
            }
        }
        .safeAreaInset(edge:.bottom,spacing:0) {
            if let error=model.errorMessage {
                HStack(alignment:.center) {
                    Image(systemName:"exclamationmark.circle").foregroundStyle(.orange)
                    Text(error).font(.system(size:12)).lineLimit(3)
                    Spacer()
                    if !model.hasConflict { Button("다시 시도") { Task { await model.retry() } } }
                    Button { model.errorMessage=nil } label:{ Image(systemName:"xmark") }.buttonStyle(.plain)
                }.padding(12).background(.bar)
            }
        }
        .preferredColorScheme(settings.colorScheme)
        .overlay { if model.busy { ProgressView().controlSize(.small).padding(14).background(.regularMaterial,in:RoundedRectangle(cornerRadius:12)) } }
    }
    private func noteRow(_ note:NoteSummary)->some View {
        VStack(alignment:.leading,spacing:6) {
            Text(note.name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ? "새로운 메모" : note.name).font(.system(size:settings.listFontSize,weight:.semibold)).lineLimit(1)
            HStack(spacing:8) {
                Text(settings.sortBy=="created" ? note.created : note.modified,format:Calendar.current.isDateInToday(settings.sortBy=="created" ? note.created : note.modified) ? .dateTime.hour().minute() : .dateTime.month(.twoDigits).day(.twoDigits)).fixedSize()
                if settings.previewLines>0 {Text(model.previews[note.id] ?? " ").lineLimit(settings.previewLines)}
            }.font(.system(size:12)).foregroundStyle(.secondary)
        }.padding(.vertical,settings.listDensity=="compact" ? 4 : (settings.listDensity=="comfortable" ? 16 : 10)).frame(maxWidth:.infinity,alignment:.leading)
        .task(id:note.modified) { await model.loadPreview(note.id) }
        .contextMenu { Button("기본 메모에서 열기") { Task { await model.chooseNote(note.id); await model.openOriginal() } } }
    }
    @ViewBuilder var editor:some View {
        if let note=model.snapshot {
            VStack(spacing:0) {
                if model.hasConflict {
                    HStack {
                        Text("다른 기기에서 변경된 내용이 있습니다. 초안을 보관했습니다.")
                        Spacer(); Button("원본 불러오기") { Task { await model.reloadOriginal() } }
                    }.font(.system(size:12)).padding(12).background(Color.orange.opacity(0.12))
                }
                if let reason=note.profile.reason {
                    HStack { Text(reason); Spacer(); Button("원본 열기") { Task { await model.openOriginal() } } }
                        .font(.system(size:11)).foregroundStyle(.secondary).padding(10).background(.quaternary.opacity(0.25))
                }
                if settings.showNoteDate { Text(note.modified,format:.dateTime.year().month(.wide).day().hour().minute())
                    .font(.system(size:12)).foregroundStyle(.secondary).padding(.top,9).padding(.bottom,5) }
                NoteEditor(text:model.text,noteID:note.id,settings:model.settings,titleTemplate:model.editorTitleTemplate,document:model.editorDocument,loadVersion:model.editorLoadVersion,bridge:model.editorBridge,editable:model.canEdit,focusToken:model.focusEditorToken,onChange:{ if model.selectedNoteID==note.id {model.edited($0,composing:$1)} })
                if settings.showCharacterCount {
                    HStack { Spacer(); Text("\(model.text.count.formatted())자 · \(model.text.components(separatedBy:"\n").count.formatted())줄").font(.caption).foregroundStyle(.secondary) }.padding(.horizontal,20).padding(.vertical,6)
                }
            }.background(Color(nsColor:.textBackgroundColor))
        } else { Text("메모 없음").foregroundStyle(.secondary).frame(maxWidth:.infinity,maxHeight:.infinity) }
    }
}
