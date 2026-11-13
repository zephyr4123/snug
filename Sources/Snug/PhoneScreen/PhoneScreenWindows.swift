// 手机屏上 Snug 自己的两块面板：盖满整块屏的窗口列表，和窗口放上来后底部的小横条。
// 跟着 PhoneDesk 的状态走：手机屏在才建，列表该露就露、该收就收，屏幕一变就重新摆位置。
// 面板不抢焦点（点它不会激活 Snug），所有桌面都在，盖在这块屏的菜单栏之上
import AppKit
import SnugCore
import SnugSystem
import SwiftUI

@MainActor
final class PhoneScreenWindows {
    private let state: AppState
    private let catalog: WindowCatalog
    private let intents: any PhoneIntents
    private var display: DisplayID?
    private var list: PhonePanel?
    private var homeBar: PhonePanel?
    private var screenObserver: (any NSObjectProtocol)?

    init(state: AppState, catalog: WindowCatalog, intents: any PhoneIntents) {
        self.state = state
        self.catalog = catalog
        self.intents = intents
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
        follow()
    }

    private func follow() {
        withObservationTracking {
            _ = state.phone
            _ = state.streamedDisplay
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.update()
                    self?.follow()
                }
            }
        }
    }

    private func update() {
        let phone = state.phone
        guard let id = phone.display, let screen = Screens.screen(for: id) else { return tearDown() }
        if id != display {
            tearDown()
            build(on: id)
        }
        guard let list, let homeBar else { return }
        list.setFrame(screen.frame, display: true)
        homeBar.setFrame(homeBarFrame(on: screen), display: true)

        let showList = phone.listVisible || phone.placed == nil
        if showList { list.orderFrontRegardless() } else { list.orderOut(nil) }
        // 列表每轮要把所有 App 的窗口读一遍，还和搬窗口共用一条队：手机没在看手机屏就不刷。
        // 不知道 UU 在推哪块屏（推流日志没读到）时照旧刷
        if showList, state.streamedDisplay == nil || state.phoneInUse {
            catalog.startRefreshing()
        } else {
            catalog.stopRefreshing()
        }
        catalog.setPaused(phone.work != nil)
        if phone.placed != nil, !showList { homeBar.orderFrontRegardless() } else { homeBar.orderOut(nil) }
    }

    private func build(on id: DisplayID) {
        display = id
        list = PhonePanel(content: FirstMouseHostingView(rootView: PhoneHomeView(state: state, catalog: catalog, intents: intents)))
        let bar = HomeBarView()
        bar.onActivate = { [weak self] in self?.intents.showList() }
        homeBar = PhonePanel(content: bar)
    }

    private func tearDown() {
        catalog.reset()
        list?.orderOut(nil)
        homeBar?.orderOut(nil)
        list = nil
        homeBar = nil
        display = nil
    }

    /// 可见区底部那一条：放上来的窗口正好让出这一条（PhoneScreenSpec.homeBarHeight）
    private func homeBarFrame(on screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        return NSRect(x: visible.minX, y: visible.minY, width: visible.width, height: PhoneScreenSpec.homeBarHeight)
    }
}

/// 不抢焦点、所有桌面都在、盖住菜单栏的面板
final class PhonePanel: NSPanel {
    init(content: NSView) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        // 菜单栏是 24，菜单栏右边的图标是 25：再高一级才盖得住
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        hasShadow = false
        isOpaque = true
        backgroundColor = PhoneStyle.backgroundNSColor
        contentView = content
    }

    // 点面板不让它变成键盘焦点：手机上的键盘输入要留给放上来的窗口
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// 面板不是键盘焦点，第一下点击也要直接生效
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// 底部小横条：点一下，或者往上滑，回到窗口列表。中间是 SF Symbols 的 chevron.compact.up
final class HomeBarView: NSView {
    /// 往上滑过这么多点算数
    static let swipeDistance: CGFloat = 12

    var onActivate: (() -> Void)?
    private var swipe: CGFloat = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        let grabber = NSImageView()
        grabber.image = NSImage(systemSymbolName: "chevron.compact.up", accessibilityDescription: "窗口列表")?
            .withSymbolConfiguration(.init(pointSize: 22, weight: .semibold))
        grabber.contentTintColor = .secondaryLabelColor
        grabber.translatesAutoresizingMaskIntoConstraints = false
        addSubview(grabber)
        NSLayoutConstraint.activate([
            grabber.centerXAnchor.constraint(equalTo: centerXAnchor),
            grabber.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("不从 nib 加载") }

    override var isOpaque: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        PhoneStyle.backgroundNSColor.setFill()
        bounds.fill()
    }

    /// 接住按下，抬起才会送到这里
    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onActivate?() }
    }

    /// 手势翻译把单指上滑变成滚动：手指往上走，滚动量是负的
    override func scrollWheel(with event: NSEvent) {
        if event.phase == .began { swipe = 0 }
        swipe += event.scrollingDeltaY
        if swipe <= -Self.swipeDistance {
            swipe = 0
            onActivate?()
        }
    }
}
