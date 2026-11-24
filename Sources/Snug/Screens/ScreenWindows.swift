// 手机、平板屏上 Snug 自己的面板，每块屏一组（ScreenPanels 跟着屏幕列表建、拆）：
// 盖满整块屏的 App 资源库，窗口放上来后底部的小横条；开着截图键时还有截图后浮在小横条上方的缩略图或提示，
// 以及裁剪时盖满整块屏的裁剪界面。
// 跟着这块屏的 Desk 状态走：屏在才建，列表该露就露、该收就收，屏幕一变（含换档）就重新摆位置。
// 面板不抢焦点（点它不会激活 Snug），所有桌面都在，盖在这块屏的菜单栏之上；
// 只在搜索、选型号时临时接收键盘，用完就还回去，手机上的键盘输入平时留给放上来的窗口
import AppKit
import SnugCore
import SnugSystem
import SwiftUI

/// 跟着 Desk 管理手机、平板的面板和电脑屏的切换器。
@MainActor
final class ScreenPanels {
    private let state: AppState
    private let catalog: AppCatalog
    private let intents: (ScreenID) -> any TouchIntents
    private var panels: [ScreenID: ScreenWindows] = [:]
    private let focus: (ScreenID, WindowInfo) -> Void
    private var desktop: [ScreenID: DesktopSwitcher] = [:]
    private var screenObserver: (any NSObjectProtocol)?

    init(state: AppState, catalog: AppCatalog, focus: @escaping (ScreenID, WindowInfo) -> Void,
         intents: @escaping (ScreenID) -> any TouchIntents) {
        self.state = state
        self.catalog = catalog
        self.intents = intents
        self.focus = focus
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateDesktop() }
        }
        follow()
    }

    private func follow() {
        withObservationTracking {
            update()
        } onChange: { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.follow() } }
        }
    }

    private func update() {
        let touch = Set(state.desks.desks.filter { $0.value.behavior.touch }.keys)
        for id in panels.keys where !touch.contains(id) {
            panels.removeValue(forKey: id)?.close()
        }
        for id in touch where panels[id] == nil {
            panels[id] = ScreenWindows(id: id, state: state, catalog: catalog, intents: intents(id))
        }
        updateDesktop()
        if state.desks.desks.isEmpty { catalog.reset() }
    }

    private func updateDesktop() {
        let active = state.screensInUse && state.accessibilityTrusted
            ? state.libraryScreens : []
        let ids = Set(active)
        for id in desktop.keys where !ids.contains(id) {
            desktop.removeValue(forKey: id)?.close()
        }
        for id in active {
            guard let display = state.desks.desks[id]?.display, let screen = Screens.screen(for: display) else {
                desktop.removeValue(forKey: id)?.close()
                continue
            }
            if desktop[id]?.display != display {
                desktop.removeValue(forKey: id)?.close()
                desktop[id] = DesktopSwitcher(id: id, display: display, catalog: catalog, intents: intents(id)) { [focus] in
                    focus(id, $0)
                }
            }
            desktop[id]?.layout(on: screen)
        }
    }
}

@MainActor
final class ScreenWindows {
    let id: ScreenID
    private let state: AppState
    private let catalog: AppCatalog
    private let pages = TouchPages()
    private let intents: any TouchIntents
    private var display: DisplayID?
    private var list: TouchPanel?
    private var homeBar: TouchPanel?
    private var homeBarView: HomeBarView?
    /// 截图后浮在小横条上方的那一块（缩略图或提示），和它此刻显示的是什么
    private var overlay: TouchPanel?
    private var overlayShown: OverlayShown?
    private var cropPanel: TouchPanel?
    private var screenObserver: (any NSObjectProtocol)?
    private var closed = false

    init(id: ScreenID, state: AppState, catalog: AppCatalog, intents: any TouchIntents) {
        self.id = id
        self.state = state
        self.catalog = catalog
        self.intents = intents
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
        // 先按此刻的状态铺一遍：屏可能在面板建出来之前就绪了，不能只等下一次变化
        update()
        follow()
    }

    /// 屏没了：拆掉面板，不再跟
    func close() {
        closed = true
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        tearDown(because: "这块屏不在列表里了，或不再是手机、平板屏")
    }

    /// 截图浮层只在截图的那块屏上
    private var screenshot: ScreenshotOverlay? { state.screenshotScreen == id ? state.screenshotOverlay : nil }

    private func follow() {
        withObservationTracking {
            _ = state.desks.desks[id]
            _ = state.desks.quitting
            _ = state.streamedDisplay
            _ = state.screensInUse
            _ = state.screenshotOverlay
            _ = state.screenshotScreen
            _ = state.config.screenshot
            _ = pages.active
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, !self.closed else { return }
                    self.update()
                    self.follow()
                }
            }
        }
    }

    private func update() {
        guard !closed else { return }
        let panel = state.panel(id)
        guard let display = panel.display else { return tearDown(because: "屏撤掉了") }
        guard let screen = Screens.screen(for: display) else { return tearDown(because: "系统里还没有 #\(display) 这块屏") }
        if display != self.display {
            tearDown(because: "换到 #\(display)")
            build(on: display)
        }
        guard let list, let homeBar else { return }
        list.setFrame(screen.frame, display: true)
        homeBar.setFrame(homeBarFrame(on: screen), display: true)
        homeBarView?.scale = ScreenFit.scale(screen: screen.frame.size)
        homeBarView?.showsCamera = state.config.screenshot

        let showList = panel.listVisible || panel.placed == nil
        let watching = state.watching(id)
        if showList { list.orderFrontRegardless() } else { list.orderOut(nil) }
        // 手机离开了就关掉搜索、型号页，交还键盘：不然在主屏上打的字会进到看不见的输入框
        if !showList || !watching { pages.close() }
        // 手机离开了还在裁剪：取消回到缩略图，不然这块屏的手势翻译一直停着，手机上又看不到裁剪界面
        if !watching, screenshot?.isCropping == true {
            Log.info("手机离开了屏（\(id)），取消这块屏上的截图裁剪")
            intents.cancelCrop()
        }
        // 只在打开页面那一下拿键盘：之后用户点了别的窗口，不能每次状态一变就抢回来
        let entering = pages.active && !list.acceptsKeys
        list.acceptsKeys = pages.active
        if entering { list.makeKey() }
        // 列表每轮要把所有 App 的窗口读一遍，还和搬窗口共用一条队：手机没在看这块屏就不为它刷
        if showList, watching {
            catalog.want(id.rawValue, busy: panel.work != nil)
        } else {
            catalog.release(id.rawValue)
        }
        let cropping = screenshot?.isCropping == true
        if panel.placed != nil, !showList, !cropping { homeBar.orderFrontRegardless() } else { homeBar.orderOut(nil) }
        updateOverlay(on: screen, hidden: showList)
        updateCrop(on: screen)
    }

    /// 截图后的浮层：缩略图靠左、正在相机键上方（点它进裁剪），提示居中（不拦点击）。
    /// 面板只有内容那么大，不挡窗口底部别的地方；回到 App 资源库、裁剪时不显示。
    /// 不显示时连面板一起拆掉：缩略图拿着解码后的整张截图，不留着占内存
    private func updateOverlay(on screen: NSScreen, hidden: Bool) {
        guard !hidden, let shot = screenshot, !shot.isCropping else {
            overlay?.orderOut(nil)
            overlay = nil
            overlayShown = nil
            return
        }
        let scale = ScreenFit.scale(screen: screen.frame.size)
        let panel = overlay ?? TouchPanel(content: NSView(), opaque: false)
        overlay = panel
        let preview = if case .preview = shot { true } else { false }
        let shown = OverlayShown(overlay: shot, scale: scale)
        if shown != overlayShown {
            overlayShown = shown
            if case .preview(let image) = shot {
                panel.contentView = FirstMouseHostingView(rootView: ScreenshotThumbnail(
                    image: NSImage(data: image.png) ?? NSImage(), scale: scale) { [weak self] in self?.intents.openCrop() })
            } else if case .notice(let notice) = shot {
                panel.contentView = NSHostingView(rootView: ScreenshotNoticeView(notice: notice, scale: scale))
            }
            panel.ignoresMouseEvents = !preview
        }
        let size = panel.contentView?.fittingSize ?? .zero
        let bar = homeBarFrame(on: screen)
        let x = preview ? bar.minX + 12 * scale : bar.midX - size.width / 2
        panel.setFrame(NSRect(origin: CGPoint(x: x, y: bar.maxY + 8 * scale), size: size), display: true)
        panel.orderFrontRegardless()
    }

    /// 裁剪界面：盖满这块屏。进裁剪时建（图片只解码这一次），出裁剪就拆
    private func updateCrop(on screen: NSScreen) {
        guard case .cropping(let image) = screenshot else {
            cropPanel?.orderOut(nil)
            cropPanel = nil
            return
        }
        let panel = cropPanel ?? TouchPanel(content: FirstMouseHostingView(rootView: CropView(
            image: NSImage(data: image.png) ?? NSImage(), pixelSize: image.size,
            onCancel: { [weak self] in self?.intents.cancelCrop() },
            onDone: { [weak self] selection in self?.intents.finishCrop(selection) }).screenPanel(id, state: state)))
        cropPanel = panel
        panel.setFrame(screen.frame, display: true)
        panel.orderFrontRegardless()
    }

    private func build(on id: DisplayID) {
        Log.info("屏（\(self.id)）的列表、小横条建在 #\(id) 上")
        display = id
        list = TouchPanel(content: FirstMouseHostingView(rootView: TouchHomeView(screen: self.id, state: state, catalog: catalog, pages: pages,
                                                                                 intents: intents).screenPanel(self.id, state: state)))
        let bar = HomeBarView()
        bar.onActivate = { [weak self] in self?.intents.showList() }
        bar.onCapture = { [weak self] in self?.intents.takeScreenshot() }
        homeBar = TouchPanel(content: bar)
        homeBarView = bar
    }

    private func tearDown(because reason: String) {
        if let display { Log.info("屏（\(id)）在 #\(display) 上的列表、小横条拆掉：\(reason)") }
        catalog.release(id.rawValue)
        pages.close()
        list?.orderOut(nil)
        homeBar?.orderOut(nil)
        overlay?.orderOut(nil)
        cropPanel?.orderOut(nil)
        list = nil
        homeBar = nil
        homeBarView = nil
        overlay = nil
        overlayShown = nil
        cropPanel = nil
        display = nil
    }

    /// 可见区底部那一条：放上来的窗口正好让出这一条（高度跟着档位缩放，见 ScreenFit.homeBarHeight）
    private func homeBarFrame(on screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        return NSRect(x: visible.minX, y: visible.minY, width: visible.width,
                      height: ScreenFit.homeBarHeight(screen: screen.frame.size))
    }

    /// 浮层上显示的截图结果和当时的倍率：换了才重建视图
    private struct OverlayShown: Equatable {
        let overlay: ScreenshotOverlay
        let scale: CGFloat
    }
}

/// 不抢焦点、所有桌面都在、盖住菜单栏的面板。截图的浮层是圆角卡片，面板透明（opaque 传 false）
final class TouchPanel: NSPanel {
    init(content: NSView, opaque: Bool = true) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        // 菜单栏是 24，菜单栏右边的图标是 25：再高一级才盖得住
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        hasShadow = false
        isOpaque = opaque
        backgroundColor = opaque ? TouchTokens.Color.backgroundNSColor : .clear
        contentView = content
    }

    /// 平时点面板不让它变成键盘焦点：手机上的键盘输入要留给放上来的窗口；搜索、选型号时才打开
    var acceptsKeys = false {
        didSet {
            // 交还键盘：收起再摆回去才会让出焦点（resignKey 只是通知，调了也还是焦点）
            guard !acceptsKeys, isKeyWindow, isVisible else { return }
            orderOut(nil)
            orderFrontRegardless()
        }
    }

    override var canBecomeKey: Bool { acceptsKeys }
    override var canBecomeMain: Bool { false }
}

/// 面板不是键盘焦点，第一下点击也要直接生效
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// 底部小横条：点一下，或者往上滑，回到 App 资源库。中间是 SF Symbols 的 chevron.compact.up；
/// 开着截图键时左边多一个相机键（camera.viewfinder），点左边这一段是截图。
/// 屏换到更宽的一档时跟着放大（scale），在手机上看着、点着、滑着都和基准宽度一样
final class HomeBarView: NSView {
    /// 基准宽度下往上滑过这么多点算数
    static let swipeDistance: CGFloat = 12

    var onActivate: (() -> Void)?
    var onCapture: (() -> Void)?
    /// 这一档比基准宽度宽几倍（ScreenFit.scale）
    var scale: CGFloat = 1 {
        didSet { if scale != oldValue { updateIcons() } }
    }
    /// 设置里开着「截图」
    var showsCamera = false {
        didSet { camera.isHidden = !showsCamera }
    }
    private let grabber = NSImageView()
    private let camera = NSImageView()
    private var swipe: CGFloat = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        updateIcons()
        grabber.contentTintColor = .secondaryLabelColor
        camera.contentTintColor = .secondaryLabelColor
        camera.imageScaling = .scaleNone
        camera.isHidden = true
        addSubview(camera)
        grabber.translatesAutoresizingMaskIntoConstraints = false
        addSubview(grabber)
        NSLayoutConstraint.activate([
            grabber.centerXAnchor.constraint(equalTo: centerXAnchor),
            grabber.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("不从 nib 加载") }

    private func updateIcons() {
        grabber.image = NSImage(systemSymbolName: "chevron.compact.up", accessibilityDescription: "App 资源库")?
            .withSymbolConfiguration(.init(pointSize: 22 * scale, weight: .semibold))
        camera.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "截图")?
            .withSymbolConfiguration(.init(pointSize: 20 * scale, weight: .semibold))
        needsLayout = true
    }

    /// 相机键的点击范围：左边整条高、一个手指宽（图标只有二十几点）。图标摆在它正中
    private var cameraArea: NSRect { NSRect(x: 0, y: 0, width: TouchTokens.Size.touchTarget * scale, height: bounds.height) }

    override func layout() {
        super.layout()
        camera.frame = cameraArea
    }

    override var isOpaque: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// 图标只是装饰，点哪儿都由横条自己接：子视图不接面板的第一下点击（acceptsFirstMouse 默认 false）
    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }

    override func draw(_ dirtyRect: NSRect) {
        TouchTokens.Color.backgroundNSColor.setFill()
        bounds.fill()
    }

    /// 接住按下，抬起才会送到这里
    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else { return }
        if showsCamera, cameraArea.contains(point) { onCapture?() } else { onActivate?() }
    }

    /// 手势翻译把单指上滑变成滚动：手指往上走，滚动量是负的
    override func scrollWheel(with event: NSEvent) {
        if event.phase == .began { swipe = 0 }
        swipe += event.scrollingDeltaY
        if swipe <= -Self.swipeDistance * scale {
            swipe = 0
            onActivate?()
        }
    }
}
