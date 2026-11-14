// 各窗口的开关。窗口都读同一份 AppState，意图交给 AppController
import AppKit

@MainActor
final class WindowRouter: Navigation {
    private let controller: AppController
    private lazy var settings = SettingsWindowController(state: controller.state, intents: controller, navigation: self)
    private lazy var welcome = WelcomeWindowController(state: controller.state)
    private lazy var about = AboutWindowController(state: controller.state, intents: controller, navigation: self)
    private lazy var update = UpdateWindowController(state: controller.state, intents: controller)
    private let legacy = LegacyNoticeWindowController()

    init(controller: AppController) { self.controller = controller }

    func openSettings() {
        controller.refreshLaunchAtLogin()
        settings.show()
    }

    func openWelcome() { welcome.show() }
    func openAbout() { about.show() }
    func openUpdate() { update.show() }

    /// 第一次打开：欢迎页关掉后记下「看过了」
    func showFirstWelcome() {
        welcome.show { [weak self] in self?.controller.markWelcomed() }
    }

    /// 旧版在运行：问清楚再开始监控（选哪个都会继续）
    func showLegacyNotice(then proceed: @escaping @MainActor () -> Void) {
        legacy.show(quitLegacy: { [weak self] in self?.controller.quitLegacyApp() }, proceed: proceed)
    }

    /// 旧版退出了：提示还挂着就收起并继续
    func legacyAppGone() { legacy.legacyGone() }
}
