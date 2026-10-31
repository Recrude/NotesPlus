import AppKit
import SwiftUI

// Compiled only by Tools/build-updater-fixture.sh; never shipped in NotesPlus.
@main struct UpdaterFixture:App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var updater=AppUpdater()
    @StateObject private var model:NotesModel
    @State private var ready=false
    init() {
        precondition(Bundle.main.bundleIdentifier?.hasPrefix("dev.notesplus.updater-fixture.")==true)
        let path=Bundle.main.object(forInfoDictionaryKey:"NotesPlusFixtureSupport") as! String
        _model=StateObject(wrappedValue:NotesModel(backend:FakeNotes(),supportURL:URL(fileURLWithPath:path),startTimer:false,debounceNanoseconds:60_000_000_000))
    }
    var body:some Scene {
        Window("NotesPlus Update Test",id:"fixture") {
            MainView(model:model).frame(minWidth:1000,minHeight:650)
                .task {
                    guard !ready else{return}; ready=true
                    delegate.model=model; updater.start()
                    await model.connect(); await model.chooseNote("n1")
                    if !UserDefaults.standard.bool(forKey:"fixtureSeeded") {
                        model.settings.lineRatio=1.85
                        model.edited("업데이트 보존 검증\n자동 저장하지 못한 테스트 초안 전체 내용")
                        model.hasConflict=true; model.persistDraft()
                        UserDefaults.standard.set(true,forKey:"fixtureSeeded")
                    }
                    let path=Bundle.main.object(forInfoDictionaryKey:"NotesPlusFixtureSupport") as! String
                    let report:[String:Any]=["version":updater.version.version,"text":model.text,"lineRatio":model.settings.lineRatio,"dirty":model.dirty]
                    let data=try! JSONSerialization.data(withJSONObject:report,options:.prettyPrinted)
                    try! data.write(to:URL(fileURLWithPath:path).appendingPathComponent("launch-\(updater.version.build).json"),options:.atomic)
                }
        }.commands {
            CommandGroup(after:.appInfo) {Button("업데이트 확인…") {updater.check()}.disabled(!updater.canCheck)}
        }
        Settings {SettingsView(settings:model.settings,model:model,updater:updater)}
    }
}
