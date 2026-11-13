// 菜单栏：只用来看状态、打开设置、退出。Snug 的操作都在手机上，Mac 这边不用管。
// 每次展开都按 AppState 现做，和设置窗口永远一致
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

    /// 菜单栏图标：SF Symbols 的 iphone.gen3（系统图标本身就是模板图，深色菜单栏自动反白）
    private static let icon: NSImage? = NSImage(systemSymbolName: "iphone.gen3", accessibilityDescription: "Snug")?
        .withSymbolConfiguration(.init(pointSize: 15, weight: .medium))

    /// 关着手机屏时图标变灰；提示文字随状态变
    private func refreshButton() {
        withObservationTracking {
            item.button?.appearsDisabled = !state.config.phoneScreen || !state.accessibilityTrusted
            item.button?.toolTip = "Snug：\(StatusText(state).headline)"
        } onChange: { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.refreshButton() } }
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let text = StatusText(state)
        menu.addItem(info(text.headline))
        if let detail = text.detail { menu.addItem(info(detail)) }
        if state.legacyAppRunning { menu.addItem(action("退出旧版 UU远程伴侣", #selector(quitLegacy), symbol: "xmark.circle")) }
        menu.addItem(.separator())
        menu.addItem(action("设置…", #selector(openSettings), key: ",", symbol: "gearshape"))
        menu.addItem(action("退出 Snug", #selector(quit), key: "q", symbol: "power"))
    }

    private func info(_ title: String) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        it.isEnabled = false
        return it
    }

    private func action(_ title: String, _ sel: Selector, key: String = "", symbol: String) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        it.target = self
        it.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        return it
    }

    @objc private func quitLegacy() { intents.quitLegacyApp() }
    @objc private func openSettings() { navigation.openSettings() }
    @objc private func quit() { intents.quit() }
}
