import SwiftUI
import AppKit

final class BetaAppDelegate:NSObject,NSApplicationDelegate {
    var model:StructuredModel?
    func applicationDidBecomeActive(_ notification:Notification){Task{@MainActor in await model?.reloadList();await model?.refresh()}}
    func applicationWillResignActive(_ notification:Notification){Task{@MainActor in model?.editor.flush();await model?.save()}}
    func applicationShouldTerminate(_ sender:NSApplication)->NSApplication.TerminateReply {
        MainActor.assumeIsolated {
            if let view=model?.editor.view,view.hasMarkedText(){view.unmarkText();model?.inputBegan();model?.edited(StructuredCodec.capture(view))}
            return model?.persistDraft()==false ? .terminateCancel:.terminateNow
        }
    }
}
#if !STRUCTURED_MODEL_TESTS
@main
#endif
struct IntegratedApp:App {
    @NSApplicationDelegateAdaptor(BetaAppDelegate.self) var delegate
    @StateObject var model=StructuredModel()
    @StateObject var updater=AppUpdater()
    var body:some Scene {
        Window("NotesPlus",id:"main") {
            IntegratedWindow(model:model,settings:model.settings)
                .onAppear{delegate.model=model;updater.start()}
                .tint(Color(red:0,green:122.0/255,blue:1))
        }.defaultSize(width:1080,height:740)
        .commands {
            CommandGroup(after:.appInfo){Button("업데이트 확인…"){updater.check()}.disabled(!updater.canCheck);Button("iCloud 연결…"){model.signIn()}}
            CommandGroup(replacing:.newItem){Button("새로운 메모"){Task{await model.create()}}.keyboardShortcut("n").disabled(!model.connected || model.loading)}
            CommandGroup(replacing:.saveItem){}
            CommandGroup(replacing:.textFormatting){Button("굵게"){model.editor.inline("bold")}.keyboardShortcut("b");Button("기울임"){model.editor.inline("italic")}.keyboardShortcut("i");Button("밑줄"){model.editor.inline("underline")}.keyboardShortcut("u")}
            CommandGroup(after:.textFormatting){Button("체크리스트"){model.editor.format("todoList")}.keyboardShortcut("l",modifiers:[.command,.shift]);Button("표 삽입"){Task{await model.tableAction("insert")}}}
            BetaTimestampCommands(settings:model.settings)
            CommandMenu("메모"){Button("다시 동기화"){Task{await model.save();await model.reloadList();await model.refresh()}}.keyboardShortcut("r");Button("초안과 백업 폴더 열기"){model.openSupportFolder()}}
        }
        Settings{SettingsView(settings:model.settings,model:model,updater:updater)}
    }
}
struct BetaTimestampCommands:Commands {
    @ObservedObject var settings:EditorSettings
    var body:some Commands{CommandGroup(after:.pasteboard){Divider();Button("타임스탬프 삽입"){NSApp.sendAction(#selector(StructuredTextView.insertTimestamp(_:)),to:nil,from:nil)}.keyboardShortcut(KeyEquivalent(settings.timestampKey.first ?? "t"),modifiers:TimestampShortcut.modifiers(settings.timestampModifiers))}}
}
struct IntegratedWindow:View {
    @ObservedObject var model:StructuredModel
    @ObservedObject var settings:EditorSettings
    @State private var visibility=NavigationSplitViewVisibility.all
    @State private var showConflict=false
    var body:some View {
        NavigationSplitView(columnVisibility:$visibility){
            List(selection:Binding(get:{model.selectedFolderID ?? "all"},set:{id in Task{await model.chooseFolder(id=="all" ? nil:id)}})){
                Section("iCloud"){
                    Label("모든 iCloud 메모",systemImage:"tray.full").tag("all")
                    ForEach(model.folders){folder in HStack{Image(systemName:folder.shared ? "folder.badge.person.crop":"folder");Text(folder.name);Spacer();if settings.showFolderCounts{Text("\(folder.count)").foregroundStyle(.secondary)}}.padding(.leading,folder.parentID==nil ? 0:12).tag(folder.id)}
                }
            }.listStyle(.sidebar).navigationSplitViewColumnWidth(min:170,ideal:210,max:300)
        } content:{
            Group {
                if settings.galleryView{
                    ScrollView{LazyVGrid(columns:[GridItem(.adaptive(minimum:180))]){ForEach(model.visibleNotes){note in Button{Task{await model.select(note.id)}}label:{row(note).padding(12).background(.background,in:RoundedRectangle(cornerRadius:10)).overlay(RoundedRectangle(cornerRadius:10).stroke(model.selectedID==note.id ? Color.accentColor:.secondary.opacity(0.2)))}.buttonStyle(.plain)}}.padding(12)}
                }else{
                    List(selection:Binding(get:{model.selectedID},set:{id in if let id{Task{await model.select(id)}}})){
                        ForEach(groups,id:\.0){group in Section{ForEach(group.1){note in row(note).tag(note.id)}}header:{if !group.0.isEmpty{Text(group.0)}}}
                    }.listStyle(.inset)
                }
            }.navigationTitle(model.folders.first(where:{$0.id==model.selectedFolderID})?.name ?? "모든 iCloud 메모")
                .navigationSubtitle("\(model.visibleNotes.count)개의 메모")
                .navigationSplitViewColumnWidth(min:210,ideal:260,max:420)
        } detail:{
            VStack(spacing:0){
                if let error=model.selectionError {HStack{Text(error);Spacer();Button("닫기"){model.selectionError=nil}}.font(.caption).padding(10).background(.orange.opacity(0.12))}
                if let note=model.snapshot {
                    if let reason=note.readOnlyReason{Text("읽기 전용 · \(reason)").font(.caption).foregroundStyle(.secondary).padding(12).frame(maxWidth:.infinity,alignment:.leading).background(.orange.opacity(0.1))}
                    if note.readOnlyReason==nil && (model.document.tables.contains{$0.protected==true} || model.document.paragraphs.contains{$0.spans.contains{$0.embed != nil || $0.style?.protected==true}}){Text("첨부와 복합 표의 원본을 유지하며 본문을 편집합니다.").font(.caption).foregroundStyle(.secondary).padding(6)}
                    if model.conflict != nil {HStack{Text("양쪽에서 같은 부분이 변경되었습니다. 작성본은 보관됩니다.");Spacer();Button("두 버전 확인"){showConflict=true}}.font(.caption).padding(10).background(.orange.opacity(0.12))}
                    if settings.showNoteDate {Text(Date(timeIntervalSince1970:(note.modified ?? note.created)/1000),format:.dateTime.year().month().day().hour().minute()).font(.caption).foregroundStyle(.secondary).padding(8)}
                    StructuredEditor(document:model.document,identity:note.id,revision:model.revision,size:settings.fontSize,ratio:settings.lineRatio,handle:model.editor,onChange:model.edited,preferences:settings.values,editable:model.canEdit,onInput:model.inputBegan)
                        .frame(maxWidth:settings.readableWidth>0 ? settings.readableWidth:.infinity)
                        .frame(maxWidth:.infinity)
                        .preferredColorScheme(settings.useDarkBackground ? settings.colorScheme:.light)
                    if settings.showCharacterCount {Text("\(model.document.paragraphs.reduce(0){$0+$1.text.count})자").font(.caption).foregroundStyle(.secondary).frame(maxWidth:.infinity,alignment:.trailing).padding(8)}
                }else{
                    ContentUnavailableView{Label("NotesPlus",systemImage:"note.text")}description:{Text(model.connected ? "메모를 선택하거나 새 메모를 만드세요.":"iCloud 메모에 연결해 편집을 시작하세요.")}actions:{Button(model.connected ? "새 메모":"iCloud 연결"){if model.connected{Task{await model.create()}}else{model.signIn()}}}
                }
                Divider();HStack{if model.loading || model.saving{ProgressView().controlSize(.small)};Text(model.status).font(.caption).foregroundStyle(.secondary).lineLimit(2);Spacer()}.padding(9)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .searchable(text:$model.search,placement:.toolbar,prompt:settings.searchScope=="title" ? "제목 검색":"제목 및 미리보기 검색")
        .toolbar {
            ToolbarItemGroup {
                Button{Task{await model.create()}}label:{Image(systemName:"square.and.pencil")}.help("새로운 메모").disabled(!model.connected || model.loading)
                if settings.showFormatTool {
                    Menu{Button("본문"){model.editor.format("body")};Button("제목"){model.editor.format("title")};Button("머리말"){model.editor.format("heading")};Button("부제목"){model.editor.format("subheading")};Divider();Button("굵게"){model.editor.inline("bold")};Button("기울임"){model.editor.inline("italic")};Button("밑줄"){model.editor.inline("underline")}}label:{Image(systemName:"textformat")}.disabled(!model.canEdit)
                    Menu{Button("글머리 목록"){model.editor.format("bulletList")};Button("번호 목록"){model.editor.format("numberedList")};Button("대시 목록"){model.editor.format("dashList")};Button("목록 해제"){model.editor.format("body")}}label:{Image(systemName:"list.bullet")}.disabled(!model.canEdit)
                }
                if settings.showChecklistTool{Button{model.editor.format("todoList")}label:{Image(systemName:"checklist")}.help("체크리스트").disabled(!model.canEdit)}
                if settings.showTableTool{Menu{Button("표 삽입"){Task{await model.tableAction("insert")}};Divider();Button("아래에 행 추가"){Task{await model.tableAction("row+")}};Button("오른쪽에 열 추가"){Task{await model.tableAction("column+")}};Button("현재 행 삭제"){Task{await model.tableAction("row-")}};Button("현재 열 삭제"){Task{await model.tableAction("column-")}}}label:{Image(systemName:"tablecells")}.disabled(!model.canEdit)}
                if settings.showShareTool{ShareLink(item:model.document.paragraphs.map(\.text).joined(separator:"\n")){Image(systemName:"square.and.arrow.up")}.help("텍스트 사본 공유").disabled(model.snapshot==nil)}
                Menu{Button("다시 동기화"){Task{await model.save();await model.reloadList();await model.refresh()}};Button("iCloud 연결…"){model.signIn()};Divider();SettingsLink{Text("설정…")}}label:{Image(systemName:"ellipsis")}
            }
        }
        .sheet(isPresented:$showConflict){BetaConflictView(model:model)}
        .preferredColorScheme(settings.colorScheme).frame(minWidth:860,minHeight:560)
    }
    private var groups:[(String,[CloudSummary])] {
        var result:[(String,[CloudSummary])]=[]
        for note in model.visibleNotes {let key=settings.groupByDate && settings.sortBy != "title" ? dateGroup(Date(timeIntervalSince1970:(settings.sortBy=="created" ? note.created:note.modified ?? note.created)/1000)):""
            if let index=result.firstIndex(where:{$0.0==key}){result[index].1.append(note)}else{result.append((key,[note]))}}
        return result
    }
    private func dateGroup(_ date:Date)->String{let c=Calendar.current;if c.isDateInToday(date){return "오늘"};if c.isDateInYesterday(date){return "어제"};return date.formatted(.dateTime.year().month(.wide))}
    private func row(_ note:CloudSummary)->some View{VStack(alignment:.leading,spacing:6){Text(note.title.isEmpty ? "새로운 메모":note.title).font(.system(size:settings.listFontSize,weight:.semibold)).lineLimit(1);if settings.previewLines>0{Text(note.preview ?? " ").font(.caption).foregroundStyle(.secondary).lineLimit(settings.previewLines)}}.padding(.vertical,settings.listDensity=="compact" ? 4:settings.listDensity=="comfortable" ? 16:10).frame(maxWidth:.infinity,alignment:.leading)}
}
struct BetaConflictView:View {
    @ObservedObject var model:StructuredModel
    @Environment(\.dismiss) private var dismiss
    var body:some View{VStack(alignment:.leading,spacing:16){Text("두 버전 확인").font(.title2);Text("선택하기 전 양쪽 원본을 Mac에 보관합니다.").foregroundStyle(.secondary);HStack(alignment:.top){version("NotesPlus 작성본",model.document);version("iCloud 현재 버전",model.conflict?.document)};HStack{Button("보관 폴더 열기"){model.openSupportFolder()};Spacer();Button("계속 편집"){dismiss()};Button("iCloud 버전 사용"){Task{await model.resolveConflict(useLocal:false);dismiss()}};Button("작성본으로 저장"){Task{await model.resolveConflict(useLocal:true);dismiss()}}.disabled(model.conflict?.readOnlyReason != nil)}}.padding(24).frame(width:850,height:550)}
    private func version(_ title:String,_ doc:CloudDocument?)->some View{VStack(alignment:.leading){Text(title).font(.headline);ScrollView{Text(doc.map{$0.paragraphs.map(\.text).joined(separator:"\n")+"\n"+$0.tables.map{$0.grid.map{$0.joined(separator:" | ")}.joined(separator:"\n")}.joined(separator:"\n\n")} ?? "불러오는 중…").textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)}}.frame(maxWidth:.infinity)}
}
