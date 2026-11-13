// 菜单栏：状态、常用开关、立即恢复屏幕、设置、退出。每次展开都按 AppState 现做，和设置窗口永远一致（修 B12）
import AppKit
import Observation
import SnugCore

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let state: AppState
    private let intents: any AppIntents
    private let navigation: any Navigation

    init(state: AppState, intents: any AppIntents, navigation: any Navigation) {
        self.state = state
        self.intents = intents
        self.navigation = navigation
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        item.button?.image = Self.icon
        refreshButton()
    }

    /// 菜单栏图标：Assets/AppIcon/MenuBarIconTemplate（模板图，深色菜单栏自动反白）；调试运行找不到资源时用系统图标
    private static let icon: NSImage = {
        let image = NSImage(named: "MenuBarIconTemplate")
            ?? NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: nil)
            ?? NSImage()
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        image.accessibilityDescription = "Snug"
        return image
    }()

    /// 图标变灰、提示文字随状态变；用 Observation 跟踪，状态变了再刷新
    private func refreshButton() {
        withObservationTracking {
            item.button?.appearsDisabled = state.config.paused
            item.button?.toolTip = "Snug：\(StatusText(state).headline)"
        } onChange: { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.refreshButton() } }
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let text = StatusText(state)
        menu.addItem(info(text.headline))
        text.details.forEach { menu.addItem(info($0)) }
        if state.legacyAppRunning { menu.addItem(action("退出旧版 UU远程伴侣", #selector(quitLegacy))) }
        menu.addItem(.separator())

        let config = state.config
        menu.addItem(action("暂停 Snug", #selector(togglePaused), on: config.paused))
        menu.addItem(action("远程时准备虚拟屏", #selector(toggleVirtual), on: config.virtualDisplayEnabled))
        let keepOnly = action("远程时只保留虚拟屏", #selector(toggleKeepOnly), on: config.keepOnlyVirtual)
        keepOnly.indentationLevel = 1
        keepOnly.isEnabled = config.virtualDisplayEnabled && state.physicalControlAvailable
        menu.addItem(keepOnly)
        menu.addItem(.separator())

        let restore = action("立即恢复屏幕", #selector(restoreScreens), key: "9")
        restore.keyEquivalentModifierMask = [.control, .option, .command]
        restore.isEnabled = state.display.physicalOff
        menu.addItem(restore)
        if state.display.layoutPending { menu.addItem(action("还原屏幕布局", #selector(restoreLayout))) }
        menu.addItem(.separator())
        menu.addItem(action("设置…", #selector(openSettings), key: ","))
        menu.addItem(action("退出 Snug", #selector(quit), key: "q"))
    }

    private func info(_ title: String) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        it.isEnabled = false
        return it
    }

    private func action(_ title: String, _ sel: Selector, key: String = "", on: Bool? = nil) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        it.target = self
        if let on { it.state = on ? .on : .off }
        return it
    }

    @objc private func togglePaused() { intents.setPaused(!state.config.paused) }
    @objc private func toggleVirtual() { intents.setVirtualDisplayEnabled(!state.config.virtualDisplayEnabled) }
    @objc private func toggleKeepOnly() { intents.setKeepOnlyVirtual(!state.config.keepOnlyVirtual) }
    @objc private func restoreScreens() { intents.restoreScreensNow() }
    @objc private func restoreLayout() { intents.restoreLayoutNow() }
    @objc private func quitLegacy() { intents.quitLegacyApp() }
    @objc private func openSettings() { navigation.openSettings(page: nil) }
    @objc private func quit() { intents.quit() }
}
