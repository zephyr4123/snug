// 菜单栏：顶上一行说清此刻的状态（远程中 · 设备 · 正在看哪块屏）；「App 资源库」给电脑屏用，在哪块屏的菜单栏点就在哪块屏打开；
// 设置、关于（同样摆到点的那块屏）、退出。手机、平板屏上的操作都在屏上的面板里。每次展开都按 AppState 现做，和设置窗口永远一致
import AppKit
import Observation
import SnugCore
import SwiftUI

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private var clickedScreen: NSScreen?
    private let state: AppState
    private let intents: any AppIntents
    private let navigation: any Navigation

    init(state: AppState, intents: any AppIntents, navigation: any Navigation) {
        self.state = state
        self.intents = intents
        self.navigation = navigation
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        if let button = item.button {
            button.image = Self.icon
            button.target = self
            button.action = #selector(showMenu)
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        }
        refreshButton()
    }

    @objc private func showMenu(_ button: NSStatusBarButton) {
        guard let anchor = menuAnchor(for: button) else { return }
        let screen = NSScreen.screens.first { $0.frame.contains(anchor) } ?? button.window?.screen
        // 先取点击坐标，等按钮结束处理这次事件，再开始菜单的事件循环。
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            button.highlight(true)
            self.clickedScreen = screen
            defer {
                self.clickedScreen = nil
                button.highlight(false)
            }
            // 给图标和菜单留出间距，避免浮层盖住图标的下缘。
            self.menu.popUp(positioning: nil, at: NSPoint(x: anchor.x, y: anchor.y - 4), in: nil)
        }
    }

    private func menuAnchor(for button: NSStatusBarButton) -> NSPoint? {
        if let event = NSApp.currentEvent, event.type == .leftMouseDown || event.type == .rightMouseDown {
            // 切屏后的第一次点击可能仍带着旧的状态栏窗口原点。用实际的点击位置重算图标左下角。
            let mouse = NSEvent.mouseLocation
            if let window = button.window, event.window === window {
                let local = button.convert(event.locationInWindow, from: nil)
                let bounds = button.bounds
                if bounds.contains(local) {
                    let bottomOffset = button.isFlipped ? bounds.maxY - local.y : local.y - bounds.minY
                    return NSPoint(x: mouse.x - (local.x - bounds.minX), y: mouse.y - bottomOffset)
                }
            }
            // 副屏的菜单栏副本可能从另一个窗口转发事件，那时只用指针所在屏。
            if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) {
                return NSPoint(x: mouse.x, y: screen.frame.maxY - NSStatusBar.system.thickness)
            }
        }
        // 键盘或辅助功能打开时没有有效的鼠标事件。
        guard let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil)).origin
    }

    /// 菜单栏图标：SF Symbols，同原型（系统图标本身就是模板图，深色菜单栏自动反白）
    private static let icon: NSImage? = NSImage(systemSymbolName: "iphone.radiowaves.left.and.right", accessibilityDescription: "Snug")?
        .withSymbolConfiguration(.init(pointSize: 14, weight: .medium))

    /// 屏都关着、没有权限时图标变灰；提示文字随状态变
    private func refreshButton() {
        withObservationTracking {
            item.button?.appearsDisabled = !state.config.screens.contains(where: \.enabled) || !state.accessibilityTrusted
            item.button?.toolTip = "Snug：\(StatusText(state).headline)"
        } onChange: { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.refreshButton() } }
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(status())
        if state.legacyAppRunning { menu.addItem(action("退出旧版 UU远程伴侣", #selector(quitLegacy), symbol: "xmark.circle")) }
        menu.addItem(.separator())
        let library = action("App 资源库", #selector(openLibrary), symbol: "square.grid.2x2")
        // 电脑屏都不在时没有地方放
        library.isEnabled = !state.libraryScreens.isEmpty
        menu.addItem(library)
        menu.addItem(.separator())
        let settings = action("设置…", #selector(openSettings), key: ",", symbol: "gearshape")
        // 有新版本：系统的菜单角标，更新在设置的通用页里
        if state.update.hasNewVersion { settings.badge = NSMenuItemBadge(string: "新版本") }
        menu.addItem(settings)
        menu.addItem(action("关于 Snug", #selector(openAbout), symbol: "info.circle"))
        menu.addItem(.separator())
        menu.addItem(action("退出 Snug", #selector(quit), key: "q", symbol: "power"))
    }

    /// 最上面一行：状态图标块 + 此刻的状态和一行说明。只看不点，所以用自定义视图（不会高亮）
    private func status() -> NSMenuItem {
        let view = NSHostingView(rootView: MenuStatusView(text: StatusText(state), status: state.status))
        view.frame.size = view.fittingSize
        view.autoresizingMask = [.width]
        let it = NSMenuItem()
        it.view = view
        return it
    }

    private func action(_ title: String, _ sel: Selector, key: String = "", symbol: String) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        it.target = self
        it.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        return it
    }

    @objc private func quitLegacy() { intents.quitLegacyApp() }
    @objc private func openSettings() { navigation.openSettings(on: clickedScreen?.displayID) }
    @objc private func openAbout() { navigation.openAbout(on: clickedScreen?.displayID) }
    /// 在哪块屏的菜单栏点，就在哪块屏打开
    @objc private func openLibrary() {
        let screen = clickedScreen
        let display = screen?.displayID
        // 认不出是哪块屏的菜单栏时，资源库按 UU 在推的电脑屏选，开错屏时从这里查
        Log.info("菜单栏：点了「App 资源库」，在\(screen.map { "「\($0.localizedName)」（display \(display.map { "\($0)" } ?? "?")）" } ?? "认不出的屏")的菜单栏")
        navigation.openLibrary(on: display)
    }
    @objc private func quit() { intents.quit() }

}

struct MenuStatusView: View {
    let text: StatusText
    let status: StatusToken

    var body: some View {
        HStack(spacing: MacTokens.Space.s) {
            Image(systemName: status.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: MacTokens.Size.iconTile, height: MacTokens.Size.iconTile)
                .background(status.color.gradient, in: RoundedRectangle(cornerRadius: MacTokens.Radius.iconTile, style: .continuous))
            VStack(alignment: .leading, spacing: MacTokens.Space.xxs) {
                Text(text.headline).font(.system(size: MacTokens.Font.body.size, weight: .medium))
                if let detail = text.detail { Text(detail).font(.system(size: MacTokens.Font.callout.size)).foregroundStyle(.secondary) }
            }
        }
        .fixedSize()
        .padding(.horizontal, 14)
        .padding(.vertical, MacTokens.Space.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
