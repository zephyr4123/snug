// 正常启动：组装 AppController、菜单栏、手机屏上的面板、窗口与退出流程。
// 第一次打开：自动设成开机启动，弹欢迎页（讲用法、请用户允许辅助功能）。之后就不用管了
import AppKit
import SnugCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller: AppController
    private let router: WindowRouter
    private let quitFlow: QuitFlow
    private var statusBar: StatusBarController?
    private var phoneScreen: PhoneScreenWindows?
    private var legacyObservers: [any NSObjectProtocol] = []
    private var termSource: (any DispatchSourceSignal)?

    init(paths: SnugPaths, previewPhone: Bool) {
        controller = AppController(paths: paths, previewPhone: previewPhone)
        router = WindowRouter(controller: controller)
        quitFlow = QuitFlow(controller: controller)
        super.init()
        controller.onQuitRequested = { [weak self] in self?.quitFlow.userQuit() }
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        Log.info("启动 Snug \(AboutView.version)，辅助功能权限：\(controller.state.accessibilityTrusted ? "已授权" : "未授权")")
        statusBar = StatusBarController(state: controller.state, intents: controller, navigation: router)
        phoneScreen = PhoneScreenWindows(state: controller.state, catalog: WindowCatalog(service: controller.windows),
                                         intents: controller)
        handleSIGTERM()
        legacyObservers = LegacyApp.observe { [weak self] running in
            self?.controller.state.legacyAppRunning = running
            if !running { self?.router.legacyAppGone() }
        }
        controller.state.legacyAppRunning = LegacyApp.isRunning
        if controller.state.legacyAppRunning {
            Log.warn("检测到旧版 UU远程伴侣 正在运行")
            router.showLegacyNotice { [weak self] in self?.startMonitoring() }
        } else {
            startMonitoring()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        quitFlow.shouldTerminate(sender)
    }

    /// kill / 活动监视器「退出」发的 SIGTERM：照用户退出走一遍收尾，把窗口放回原处
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
        controller.refreshLaunchAtLogin()
        if !controller.state.config.welcomed {
            if !controller.state.launchAtLogin { controller.setLaunchAtLogin(true) }
            router.showFirstWelcome()
        } else if !controller.state.accessibilityTrusted {
            router.openWelcome()
        }
    }
}
