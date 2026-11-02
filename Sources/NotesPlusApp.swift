import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var settings:EditorSettings
    @ObservedObject var model:StructuredModel
    @ObservedObject var updater:AppUpdater
    @State private var message:String?
    @State private var confirmReset=false
    private let sections=["기본","서체·여백","목록","입력","시간","화면","저장","Apple 관리","업데이트"]
    private var fontNames:[String] { NSFontManager.shared.availableFontFamilies.sorted() }
    var body:some View {
        VStack(spacing:0) {
            HStack {
                Text("NotesPlus 설정").font(.title2.weight(.semibold))
                Spacer()
                Menu {
                    Button("설정 내보내기…",action:exportSettings)
                    Button("설정 불러오기…",action:importSettings)
                    Divider()
                    Button("전체 기본값 복원…") { confirmReset=true }
                } label:{ Image(systemName:"ellipsis.circle") }.menuStyle(.borderlessButton).fixedSize()
            }.padding(.horizontal,24).padding(.top,20).padding(.bottom,12)
            ScrollViewReader { reader in
                HStack(spacing:16) {
                    ForEach(sections,id:\.self) { name in Button(name) { withAnimation { reader.scrollTo(name,anchor:.top) } }.buttonStyle(.borderless) }
                    Spacer(minLength:0)
                }.padding(.horizontal,24).padding(.bottom,14)
                Divider()
                ScrollView {
                    VStack(alignment:.leading,spacing:20) {
                        Text("변경 즉시 적용됩니다. 표시·입력 설정은 이 Mac의 NotesPlus에만 적용됩니다.")
                            .font(.callout).foregroundStyle(.secondary)
                        general.id("기본")
                        typography.id("서체·여백")
                        lists.id("목록")
                        typing.id("입력")
                        timestamp.id("시간")
                        appearance.id("화면")
                        saving.id("저장")
                        appleManaged.id("Apple 관리")
                        updates.id("업데이트")
                    }.padding(24)
                }
            }
            Divider()
            HStack {
                Text(updater.version.label).foregroundStyle(.secondary)
                Spacer()
                Button("업데이트 확인…") {updater.check()}.disabled(!updater.canCheck)
            }.font(.callout).padding(.horizontal,24).padding(.vertical,12)
        }
        .frame(width:760,height:760)
        .tint(Color(red:0,green:122.0/255,blue:1))
        .preferredColorScheme(settings.colorScheme)
        .alert("설정",isPresented:Binding(get:{message != nil},set:{if !$0 {message=nil}})) { Button("확인") {message=nil} } message:{Text(message ?? "")}
        .confirmationDialog("NotesPlus의 모든 설정을 기본값으로 되돌릴까요?",isPresented:$confirmReset,titleVisibility:.visible) {
            Button("기본값 복원") { settings.reset() }
        } message:{Text("메모 내용과 Apple 기본 메모의 설정은 유지됩니다.")}
    }
    private func section<Content:View>(_ title:String,kind:String="Extension",keys:[PartialKeyPath<Preferences>]=[],@ViewBuilder content:()->Content)->some View {
        VStack(alignment:.leading,spacing:10) {
            HStack {
                Text(title).font(.headline)
                Text(kind).font(.caption).foregroundStyle(.secondary).padding(.horizontal,7).padding(.vertical,3).background(.quaternary,in:Capsule())
                Spacer()
                if !keys.isEmpty { Button("초기화") {settings.reset(keys)}.font(.caption).buttonStyle(.borderless) }
            }
            VStack(alignment:.leading,spacing:13) { content() }.padding(16).frame(maxWidth:.infinity,alignment:.leading)
                .background(.background,in:RoundedRectangle(cornerRadius:10))
                .overlay(RoundedRectangle(cornerRadius:10).stroke(Color(nsColor:.separatorColor).opacity(0.5)))
        }
    }
    private func note(_ text:String)->some View { Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true) }
    private func decimal(_ title:String,_ binding:Binding<Double>,range:ClosedRange<Double>,step:Double,unit:String="",digits:Int=0)->some View {
        HStack {
            Text(title).frame(width:150,alignment:.leading)
            Slider(value:binding,in:range,step:step).accessibilityLabel(title)
            TextField(title,value:binding,format:.number.precision(.fractionLength(digits)))
                .textFieldStyle(.roundedBorder).multilineTextAlignment(.trailing).frame(width:58)
                .accessibilityLabel(title+" 값")
            Text(unit).foregroundStyle(.secondary).frame(width:26,alignment:.leading)
        }
    }
    private var general:some View {
        section("기본 메모 옵션",kind:"NotesPlus에 적용",keys:[\Preferences.sortBy,\.sortAscending,\.groupByDate,\.galleryView,\.newNoteStyle,\.defaultFolderID,\.useDarkBackground]) {
            Picker("메모 정렬 기준",selection:$settings.values.sortBy) { Text("수정일").tag("modified"); Text("생성일").tag("created"); Text("제목").tag("title") }
            Picker("정렬 방향",selection:$settings.values.sortAscending) {
                Text(settings.sortBy=="title" ? "가나다순" : "오래된 메모 먼저").tag(true)
                Text(settings.sortBy=="title" ? "가나다 역순" : "최신 메모 먼저").tag(false)
            }
            Toggle("날짜별로 그룹화",isOn:$settings.values.groupByDate).disabled(settings.sortBy=="title")
            if settings.sortBy=="title" { note("제목으로 정렬할 때는 날짜 그룹화를 잠시 사용하지 않습니다.") }
            Picker("메모 보기",selection:$settings.values.galleryView) { Text("목록").tag(false); Text("갤러리").tag(true) }
            Divider()
            Picker("새 메모의 첫 줄",selection:$settings.values.newNoteStyle) {
                Text("제목").tag("title"); Text("머리말").tag("heading"); Text("부제목").tag("subheading"); Text("본문").tag("body")
            }
            Picker("새 메모 기본 위치",selection:$settings.values.defaultFolderID) {
                Text("현재 선택한 폴더").tag("")
                if !settings.defaultFolderID.isEmpty, !model.folders.contains(where:{$0.id==settings.defaultFolderID}) { Text("사용할 수 없는 폴더 · 다시 선택하세요").tag(settings.defaultFolderID) }
                ForEach(model.folders.filter{!$0.shared && $0.name != "Recently Deleted"}) { Text("\($0.account) / \($0.name)").tag($0.id) }
            }
            note("첫 줄의 제목 서식은 새 메모에 저장됩니다. 기본 위치는 NotesPlus에서 ⌘N으로 만들 때 적용됩니다.")
            Toggle("다크 모드에서 메모 본문도 어둡게 표시",isOn:$settings.values.useDarkBackground)
        }
    }
    private var updates:some View {
        section("버전 및 업데이트",kind:"NotesPlus") {
            Text("NotesPlus \(updater.version.version)")
            Toggle("새 버전 소식 자동 확인",isOn:Binding(get:{updater.automaticChecks},set:{updater.setAutomaticChecks($0)}))
            if let version=updater.availableVersion {
                Text("새 버전 \(version)을 사용할 수 있습니다.").foregroundStyle(.blue)
            }
            if let date=updater.lastCheck {
                Text("마지막 확인: \(date.formatted(date:.abbreviated,time:.shortened))").font(.callout).foregroundStyle(.secondary)
            }
            if let message=updater.message {note(message)}
            note("새 버전의 변경 내용을 확인한 뒤 설치할 수 있습니다. 메모·초안·설정을 유지하고 앱을 교체한 뒤 다시 실행합니다.")
        }
    }
    private var typography:some View {
        section("서체와 본문 여백",keys:[\Preferences.fontName,\.fontWeight,\.fontSize,\.lineRatio,\.paragraphSpacing,\.characterSpacing,\.horizontalPadding,\.verticalPadding,\.readableWidth,\.tabWidth]) {
            Picker("글꼴",selection:$settings.values.fontName) {
                Text("시스템 기본").tag("system")
                if settings.fontName != "system", !fontNames.contains(settings.fontName) { Text(settings.fontName).tag(settings.fontName) }
                ForEach(fontNames,id:\.self) { Text($0).tag($0) }
            }
            Picker("굵기",selection:$settings.values.fontWeight) { Text("보통").tag("regular"); Text("중간").tag("medium"); Text("굵게").tag("semibold") }
            decimal("기본 글자 크기",$settings.values.fontSize,range:10...40,step:0.5,unit:"pt",digits:1)
            decimal("행간 배율",$settings.values.lineRatio,range:1...3,step:0.05,unit:"배",digits:2)
            note("현재 줄 높이: \((settings.fontSize*settings.lineRatio).formatted(.number.precision(.fractionLength(1)))) pt · 글자 크기 × 행간 배율")
            decimal("문단 뒤 간격",$settings.values.paragraphSpacing,range:0...40,step:1,unit:"pt")
            decimal("자간",$settings.values.characterSpacing,range:-1...5,step:0.1,unit:"pt",digits:1)
            Divider()
            decimal("좌우 여백",$settings.values.horizontalPadding,range:8...100,step:2,unit:"pt")
            decimal("위아래 여백",$settings.values.verticalPadding,range:0...80,step:1,unit:"pt")
            Toggle("읽기 편한 본문 너비로 제한",isOn:Binding(get:{settings.readableWidth>0},set:{settings.readableWidth=$0 ? 640 : 0}))
            if settings.readableWidth>0 { decimal("최대 본문 너비",$settings.values.readableWidth,range:320...1200,step:20,unit:"pt") }
            Picker("탭 너비",selection:$settings.values.tabWidth) { Text("2칸").tag(2); Text("4칸").tag(4); Text("8칸").tag(8) }
            note("글꼴·크기·행간·여백은 표시 설정입니다. 다른 기기의 본문 서식을 바꾸지 않습니다.")
        }
    }
    private var lists:some View {
        section("목록 자동화",keys:[\Preferences.numberPeriod,\.numberParen,\.starBullet,\.dashBullet,\.plusBullet,\.bulletSymbol,\.continueBullets,\.exitEmptyList,\.preserveIndent,\.tabInsertsSpaces]) {
            HStack {
                Text("빠른 설정").foregroundStyle(.secondary)
                Spacer()
                Button("번호만 자동") {settings.listPreset("numbers")}
                Button("모두 직접 입력") {settings.listPreset("manual")}

            }
            Divider()
            Toggle("1. + 공백  →  실제 번호 목록으로 시작",isOn:$settings.values.numberPeriod)
            Toggle("1) + 공백  →  실제 번호 목록으로 시작",isOn:$settings.values.numberParen)
            Toggle("* + 공백  →  글머리 기호로 변환",isOn:$settings.values.starBullet)
            Toggle("- + 공백  →  글머리 기호로 변환",isOn:$settings.values.dashBullet)
            Toggle("+ + 공백  →  글머리 기호로 변환",isOn:$settings.values.plusBullet)
            note("각 입력 기호를 따로 설정할 수 있습니다. 기본값은 번호만 자동 변환하며, *는 그대로 입력합니다.")
            note("점 목록은 실제 글머리 목록으로, -는 실제 대시 목록으로 저장합니다.")
            Divider()
            Toggle("글머리 기호 다음 줄도 자동으로 이어쓰기",isOn:$settings.values.continueBullets)
            Toggle("빈 목록 항목에서 Return을 누르면 목록 끝내기",isOn:$settings.values.exitEmptyList)
            Toggle("새 줄에 앞줄의 공백·탭 들여쓰기 유지",isOn:$settings.values.preserveIndent)
            Toggle("Tab 키로 탭 문자 대신 공백 입력",isOn:$settings.values.tabInsertsSpaces)
            note("줄 시작에서 직접 입력할 때 적용됩니다. 붙여넣은 텍스트는 변환하지 않습니다. 번호는 메모의 실제 번호 목록으로 저장됩니다. iPhone에서도 목록으로 이어서 편집할 수 있습니다.")
        }
    }
    private var typing:some View {
        section("입력과 자동 보정",keys:[\Preferences.spellChecking,\.grammarChecking,\.spellingCorrection,\.smartQuotes,\.smartDashes,\.textReplacement,\.textCompletion,\.smartInsertDelete]) {
            Toggle("입력하는 동안 맞춤법 검사",isOn:$settings.values.spellChecking)
            Toggle("맞춤법과 함께 문법 검사",isOn:$settings.values.grammarChecking).disabled(!settings.spellChecking)
            Toggle("맞춤법 자동 수정",isOn:$settings.values.spellingCorrection)
            Toggle("스마트 따옴표",isOn:$settings.values.smartQuotes)
            Toggle("스마트 대시",isOn:$settings.values.smartDashes)
            Toggle("macOS 텍스트 대치 사용",isOn:$settings.values.textReplacement)
            Toggle("인라인 텍스트 완성 사용",isOn:$settings.values.textCompletion)
            Toggle("잘라내기·붙여넣기 때 공백 자동 조절",isOn:$settings.values.smartInsertDelete)
            note("검사·보정 언어와 텍스트 대치 사전은 macOS 설정을 따릅니다. 한글 조합 중에는 목록 변환과 자동 저장을 미룹니다.")
        }
    }
    private var timestamp:some View {
        section("타임스탬프",keys:[\Preferences.timestampFormat,\.timestampKey,\.timestampModifiers]) {
            HStack {
                Text("날짜·시간 형식").frame(width:150,alignment:.leading)
                TextField("yyyy/MM/dd HH:mm",text:$settings.values.timestampFormat)
                    .textFieldStyle(.roundedBorder).font(.system(.body,design:.monospaced))
                    .accessibilityLabel("타임스탬프 형식")
            }
            HStack {
                Text("빠른 선택").foregroundStyle(.secondary)
                Button(TimestampFormat.standard) {settings.timestampFormat=TimestampFormat.standard}
                Button(TimestampFormat.compact) {settings.timestampFormat=TimestampFormat.compact}
            }
            HStack {
                Text("삽입 단축키").frame(width:150,alignment:.leading)
                Picker("보조 키",selection:$settings.values.timestampModifiers) {
                    ForEach(TimestampShortcut.combinations,id:\.self) { Text(TimestampShortcut.label($0)).tag($0) }
                }.labelsHidden().frame(width:135).accessibilityLabel("타임스탬프 보조 키")
                Picker("키",selection:$settings.values.timestampKey) {
                    ForEach(TimestampShortcut.keys,id:\.self) { Text($0.uppercased()).tag($0) }
                }.labelsHidden().frame(width:85).accessibilityLabel("타임스탬프 키")
                Spacer()
            }
            note("본문의 커서 위치에 Mac의 현재 날짜·시간을 삽입합니다. yyyy: 연도 · MM: 월 · dd: 일 · HH: 24시간 · mm: 분 · ss: 초")
            note("기본 단축키는 ⌃⌘T입니다. 주요 편집 단축키와 겹치는 조합은 기본값으로 돌아갑니다.")
        }
    }
    private var appearance:some View {
        section("화면과 도구 모음",keys:[\Preferences.appearance,\.showNoteDate,\.showCharacterCount,\.showFolderCounts,\.previewLines,\.listDensity,\.listFontSize,\.searchScope,\.showFormatTool,\.showChecklistTool,\.showTableTool,\.showAttachmentTool,\.showShareTool]) {
            Picker("앱 테마",selection:$settings.values.appearance) { Text("시스템 설정").tag("system"); Text("라이트").tag("light"); Text("다크").tag("dark") }
            Toggle("본문 위에 수정 날짜 표시",isOn:$settings.values.showNoteDate)
            Toggle("본문 아래에 글자 수 표시",isOn:$settings.values.showCharacterCount)
            Toggle("폴더별 메모 개수 표시",isOn:$settings.values.showFolderCounts)
            Picker("목록 미리보기",selection:$settings.values.previewLines) { Text("숨김").tag(0); Text("1줄").tag(1); Text("2줄").tag(2); Text("3줄").tag(3) }
            Picker("목록 간격",selection:$settings.values.listDensity) { Text("좁게").tag("compact"); Text("보통").tag("standard"); Text("넓게").tag("comfortable") }
            decimal("목록 제목 크기",$settings.values.listFontSize,range:11...20,step:1,unit:"pt")
            Picker("검색 범위",selection:$settings.values.searchScope) { Text("제목만").tag("title"); Text("제목과 불러온 미리보기").tag("preview") }
            Divider()
            Text("도구 모음에 표시").font(.subheadline.weight(.medium))
            Toggle("서식",isOn:$settings.values.showFormatTool)
            Toggle("체크리스트",isOn:$settings.values.showChecklistTool)
            Toggle("표",isOn:$settings.values.showTableTool)
            Toggle("텍스트 사본 공유",isOn:$settings.values.showShareTool)
            note("서식·체크리스트·표는 NotesPlus에서 편집합니다. 이미지·스캔 등 첨부 편집은 이 베타에서 지원하지 않습니다.")
        }
    }
    private var saving:some View {
        section("자동 저장과 다시 열기",keys:[\Preferences.autosaveDelay,\.autosaveMaxInterval,\.syncInterval,\.restoreLastNote]) {
            decimal("입력 후 저장 대기",$settings.values.autosaveDelay,range:0.3...3,step:0.05,unit:"초",digits:2)
            decimal("연속 입력 중 저장",$settings.values.autosaveMaxInterval,range:3...30,step:1,unit:"초")
            decimal("다른 기기 변경 확인",$settings.values.syncInterval,range:2...30,step:1,unit:"초")
            Toggle("실행할 때 마지막 메모 다시 열기",isOn:$settings.values.restoreLastNote)
            note("자동 저장은 항상 켜져 있습니다. 메모를 이동하면 저장을 이어가고, 종료할 때 미전송 입력은 로컬 초안으로 보관해 다음 실행에서 전송합니다. 확인 간격은 이 앱의 조회 주기이며 iCloud 전송 속도를 바꾸지는 않습니다.")
            HStack { Text("미저장 초안과 저장 전 백업"); Spacer(); Button("보관 폴더 열기") {model.openSupportFolder()} }
        }
    }
    private func managed(_ title:String,_ description:String)->some View {
        VStack(alignment:.leading,spacing:3) { Text(title); note(description) }
    }
    private var appleManaged:some View {
        section("Apple 기본 메모에서 관리",kind:"기본 앱 전용") {
            note("아래 옵션은 Apple 메모의 계정·보안·시스템 기능에 속합니다. NotesPlus에서 변경하는 스위치가 아니며, 기본 메모 → 설정(⌘,)에서 관리합니다.")
            managed("기본 계정", "Siri가 메모를 만들 때 사용하는 계정입니다. NotesPlus의 새 메모 위치와 별개입니다.")
            managed("‘나의 Mac’ 계정 활성화", "Apple 메모의 로컬 계정 설정입니다. 이 베타는 개인 iCloud 계정의 메모를 불러옵니다.")
            managed("마지막 빠른 메모 다시 열기", "핫 코너·시스템 단축키로 여는 Apple 빠른 메모의 동작입니다.")
            managed("완료한 체크리스트 항목 자동 정렬", "Apple의 체크리스트 항목을 완료 시 아래로 이동합니다.")
            managed("멘션 알림 허용", "공유 메모에서 이름이 언급될 때 Apple 메모가 보내는 알림입니다.")
            managed("잠긴 메모 · 암호 설정 / 변경 / 재설정", "Apple 메모의 계정별 잠금 설정입니다. 잠긴 메모는 기본 앱에서 편집합니다.")
            managed("Touch ID 사용", "잠긴 메모의 생체 인증 설정입니다.")
            managed("링크·선택 하이라이트 색상", "macOS 시스템 설정 → 화면 모드에서 관리합니다. NotesPlus 아이콘과 강조색은 파란색입니다.")
            HStack {
                Spacer()
                Button("기본 메모 열기") { NSWorkspace.shared.open(URL(fileURLWithPath:"/System/Applications/Notes.app")) }
                Link("Apple 설정 안내",destination:URL(string:"https://support.apple.com/ko-kr/guide/notes/apd97da26aed/mac")!)
            }
        }
    }
    private func exportSettings() {
        let panel=NSSavePanel(); panel.allowedContentTypes=[.json]; panel.nameFieldStringValue="NotesPlus-settings.json"
        guard panel.runModal() == .OK,let url=panel.url else{return}
        do {try settings.exportData().write(to:url,options:.atomic)} catch {message=error.localizedDescription}
    }
    private func importSettings() {
        let panel=NSOpenPanel(); panel.allowedContentTypes=[.json]; panel.allowsMultipleSelection=false
        guard panel.runModal() == .OK,let url=panel.url else{return}
        do {try settings.importData(Data(contentsOf:url))} catch {message="설정을 불러오지 못했습니다. "+error.localizedDescription}
    }
}
