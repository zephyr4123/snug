// 正常启动：组装 AppController、菜单栏、手机屏上的面板、窗口与退出流程。
// 第一次打开：自动设成开机启动，弹欢迎页（讲用法、请用户允许辅助功能）。之后就不用管了。
// 用户亲手打开（双击、Dock、启动台、聚焦搜索），或者运行中再点一次：弹设置页，状态、开关、权限一眼看全。开机自启不弹。
// 刚换了版本（应用内更新后重新打开、手动替换）：弹「关于 Snug」，新版本号一眼可见
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
    /// 这次是开机自启（登录项拉起的），不是用户亲手打开的
    private var launchedAtLogin = false

    init(paths: SnugPaths, previewPhone: Bool) {
        controller = AppController(paths: paths, previewPhone: previewPhone)
        router = WindowRouter(controller: controller)
        quitFlow = QuitFlow(controller: controller)
        super.init()
        controller.onQuitRequested = { [weak self] in self?.quitFlow.userQuit() }
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        launchedAtLogin = Self.launchedAsLoginItem
        Log.info("启动 Snug \(Updater.current?.description ?? "开发版")（\(launchedAtLogin ? "开机自启" : "手动打开")），"
            + "辅助功能权限：\(controller.state.accessibilityTrusted ? "已授权" : "未授权")")
        statusBar = StatusBarController(state: controller.state, intents: controller, navigation: router)
        phoneScreen = PhoneScreenWindows(state: controller.state, catalog: WindowCatalog(service: controller.windows),
                                         intents: controller)
        handleSIGTERM()
        controller.updater.onNewVersion = { [weak self] userInitiated in self?.router.showUpdate(activating: userInitiated) }
        controller.updater.onInstalled = { [weak self] in self?.quitFlow.userQuit() }
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

    /// 运行中再双击、点 Dock 里的 Snug：弹设置页。Snug 没有常驻窗口，不处理的话这一下看起来毫无反应
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        router.openSettings()
        return false
    }

    /// 登录项拉起 App 时，打开 App 的 Apple Event 里带着 keyAELaunchedAsLogInItem。只在启动过程中读得到
    private static var launchedAsLoginItem: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventID == AEEventID(kAEOpenApplication) else { return false }
        return event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
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
        controller.updater.check(userInitiated: false, waitForNetwork: launchedAtLogin)
        let updated = controller.recordVersion()
        if !controller.state.config.welcomed {
            if !controller.state.launchAtLogin { controller.setLaunchAtLogin(true) }
            router.showFirstWelcome()
        } else if !controller.state.accessibilityTrusted {
            router.openWelcome()
        } else if updated {
            router.openAbout()
        } else if !launchedAtLogin {
            router.openSettings()
        }
    }
}
