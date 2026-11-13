// 正常启动：组装 AppController、菜单栏、热键、窗口与退出流程。
// 首次启动顺序：导览 →（缺权限时）授权引导 → 设置
import AppKit
import SnugCore
import SnugDisplays

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller: AppController
    private let router: WindowRouter
    private let quitFlow: QuitFlow
    private var statusBar: StatusBarController?
    private var hotkey: Hotkey?
    private var legacyObservers: [any NSObjectProtocol] = []
    private var termSource: (any DispatchSourceSignal)?

    init(paths: SnugPaths) {
        controller = AppController(paths: paths, store: ConfigStore(url: paths.config), sensor: UUSensor(),
                                   watchdog: WatchdogAgent(bundle: .main, paths: paths))
        router = WindowRouter(controller: controller)
        quitFlow = QuitFlow(controller: controller)
        super.init()
        controller.onQuitRequested = { [weak self] in self?.quitFlow.userQuit() }
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "开发版"
        Log.info("启动 Snug \(version)，辅助功能权限：\(UUAccessibility.isTrusted ? "已授权" : "未授权")")
        statusBar = StatusBarController(state: controller.state, intents: controller, navigation: router)
        let hotkey = Hotkey { [weak self] in self?.controller.restoreScreensNow() }
        hotkey.register()
        self.hotkey = hotkey
        controller.refreshLaunchAtLogin()
        handleSIGTERM()
        legacyObservers = LegacyApp.observe { [weak self] running in
            self?.controller.state.legacyAppRunning = running
        }
        controller.state.legacyAppRunning = LegacyApp.isRunning
        if controller.state.legacyAppRunning {
            // 两个一起跑会互相改屏幕：先问清楚再开始监控
            Log.warn("检测到旧版 UU远程伴侣 正在运行")
            router.showLegacyNotice { [weak self] in self?.startMonitoring() }
        } else {
            startMonitoring()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        quitFlow.shouldTerminate(sender)
    }

    /// kill / 活动监视器「退出」发的 SIGTERM：照用户退出走一遍收尾，不直接死掉留下熄灭的屏幕
    private func handleSIGTERM() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                Log.info("收到 SIGTERM，先收尾再退出")
                self?.quitFlow.userQuit()
            }
        }
        source.resume()
        termSource = source
    }

    private func startMonitoring() {
        controller.start()
        let state = controller.state
        let setup = { [weak self] in
            guard let self else { return }
            if state.accessibilityTrusted {
                router.openSettings(page: nil)
            } else {
                router.showPermissions(autoClose: true) { [weak self] in self?.router.openSettings(page: nil) }
            }
        }
        if state.config.tourShown {
            if !state.accessibilityTrusted { router.showPermissions(autoClose: true, onDone: nil) }
        } else {
            router.showTour(onDone: setup)
        }
    }
}
