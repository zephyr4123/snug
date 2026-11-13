// 各窗口的开关。窗口都读同一份 AppState，意图交给 AppController
import AppKit
import SnugCore

@MainActor
final class WindowRouter: Navigation {
    private let controller: AppController
    private lazy var settings = SettingsWindowController(state: controller.state, intents: controller, navigation: self)
    private lazy var permissions = PermissionsWindowController(state: controller.state)
    private let tour = TourController()
    private let about = AboutWindowController()
    private let legacy = LegacyNoticeWindowController()

    init(controller: AppController) { self.controller = controller }

    func openSettings(page: SettingsPage?) {
        controller.refreshLaunchAtLogin()
        settings.show(page: page)
    }

    func openPermissions() { permissions.show(autoClose: false, onDone: nil) }
    func openTour() { showTour(onDone: nil) }
    func openAbout() { about.show() }

    func showPermissions(autoClose: Bool, onDone: (() -> Void)?) {
        permissions.show(autoClose: autoClose, onDone: onDone)
    }

    func showTour(onDone: (() -> Void)?) {
        tour.show { [weak self] in
            self?.controller.markTourShown()
            onDone?()
        }
    }

    /// 旧版在运行：问清楚再开始监控（选哪个都会继续）
    func showLegacyNotice(then proceed: @escaping @MainActor () -> Void) {
        legacy.show(quitLegacy: { [weak self] in self?.controller.quitLegacyApp() }, proceed: proceed)
    }
}
