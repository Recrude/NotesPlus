import AppKit
import Combine
import Sparkle

struct AppVersion {
    let version:String
    let build:String
    init(bundle:Bundle = .main) {
        version=bundle.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "개발 버전"
        build=bundle.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "—"
    }
    var label:String {"버전 \(version) (\(build))"}
}

@MainActor final class AppUpdater:NSObject,ObservableObject,SPUUpdaterDelegate {
    @Published private(set) var canCheck=false
    @Published private(set) var automaticChecks=false
    @Published private(set) var lastCheck:Date?
    @Published private(set) var availableVersion:String?
    @Published private(set) var message:String?
    let version=AppVersion()
    private var controller:SPUStandardUpdaterController!
    private var started=false

    override init() {
        super.init()
        controller=SPUStandardUpdaterController(startingUpdater:false,updaterDelegate:self,userDriverDelegate:nil)
        controller.updater.publisher(for:\.canCheckForUpdates).assign(to:&$canCheck)
        controller.updater.publisher(for:\.automaticallyChecksForUpdates).assign(to:&$automaticChecks)
        controller.updater.publisher(for:\.lastUpdateCheckDate).assign(to:&$lastCheck)
    }
    func start() {guard !started else{return}; started=true; controller.startUpdater()}
    func check() {
        guard canCheck else{return}
        message=nil
        controller.checkForUpdates(nil)
    }
    func setAutomaticChecks(_ enabled:Bool) {controller.updater.automaticallyChecksForUpdates=enabled}
    func updater(_ updater:SPUUpdater,didFindValidUpdate item:SUAppcastItem) {
        availableVersion=item.displayVersionString; message=nil
    }
    func updaterDidNotFindUpdate(_ updater:SPUUpdater) {availableVersion=nil}
    func updater(_ updater:SPUUpdater,didAbortWithError error:Error) {
        let code=(error as NSError).code
        if code != SUError.noUpdateError.rawValue && code != SUError.installationCanceledError.rawValue {message=error.localizedDescription}
    }
    // Sparkle asks NSApplication to terminate normally. AppDelegate retains control
    // of flushing edits, preserving drafts, and allowing the user to cancel quitting.
}
