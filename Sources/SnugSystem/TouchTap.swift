// 手势翻译的系统部分：一个事件监听，只接管远控注入、在某块范围里按下的鼠标左键（每块要翻译手势的屏一块），
// 交给 TouchTranslator 判断，再照它说的补发点击、右键或滚动（事件怎么读、怎么拼见 TouchEvents）。本机的触控板、鼠标一律不碰。
// 跑在独立线程上：主线程会被建屏、搬窗口卡住，监听回调一慢，系统会让全机的鼠标跟着卡
import CoreGraphics
import Foundation
import os
import SnugCore

/// 主线程用的开关。每次开启是一个独立的监听会话：关掉马上再开，新旧两个线程互不共用状态
@MainActor
public final class TouchTap {
    /// 手势翻译管的范围（CGEvent 坐标），每块要翻译手势的屏一块。主线程写，监听线程读
    private let regions = OSAllocatedUnfairLock<[TouchRegion]>(initialState: [])
    private var session: TapSession?
    /// 接管哪些进程注入的事件：各家已登记的远控
    private let injectors: [InjectedEventSource]
    /// 手机上点了屏上那个窗口的关闭按钮（核对过、点击已经吞掉了），交回窗口编号：在主线程上调
    public var onCloseWindow: ((UInt32) -> Void)?
    /// 在 Codex 窗口横向滑动（事件已经吞掉），交回窗口编号和要展开还是关闭
    public var onSetSidebar: ((UInt32, Bool) -> Void)?

    public init(injectors: [InjectedEventSource]) {
        self.injectors = injectors
    }

    /// 只在这几块范围里翻译手势，一块都没有就关掉监听。范围变了（换档、屏幕重排）照样调，监听不用重开。
    /// 要翻译却建不起事件监听（多半是没有辅助功能权限）时交回 false，下次调用再试
    public func setRegions(_ regions: [TouchRegion]) -> Bool {
        self.regions.withLock { $0 = regions }
        guard !regions.isEmpty else {
            stop()
            return true
        }
        return start()
    }

    /// 起监听线程，等它报告监听建没建成
    private func start() -> Bool {
        guard session == nil else { return true }
        let next = TapSession(
            regions: regions,
            injectors: injectors,
            closeWindow: { [weak self] window in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.onCloseWindow?(window) } }
            },
            setSidebar: { [weak self] window, open in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.onSetSidebar?(window, open) } }
            }
        )
        guard next.start() else {
            Log.error("手势翻译开不起来：建事件监听失败（多半是没有辅助功能权限）")
            return false
        }
        session = next
        Log.info("手势翻译已开启（只接管 \(injectors.map(\.executableName).joined(separator: "、")) 发来、在 Snug 屏里的操作）")
        return true
    }

    private func stop() {
        guard let session else { return }
        session.stop()
        self.session = nil
        Log.info("手势翻译已关闭")
    }
}

/// 一次监听：自己的线程、自己的 run loop、自己的状态机。除了 start / stop，其余都只在这个线程上跑
private final class TapSession: @unchecked Sendable {
    private let regions: OSAllocatedUnfairLock<[TouchRegion]>
    private let closeWindow: @Sendable (UInt32) -> Void
    private let setSidebar: @Sendable (UInt32, Bool) -> Void
    /// 监听线程的 run loop：start 等它建好才返回，之后只读
    private var runLoop: CFRunLoop?

    // 以下只在监听线程上访问
    private var tap: CFMachPort?
    private var translator = TouchTranslator()
    private var heldPress: CGEvent?
    private var coastTimer: CFRunLoopTimer?
    private var injected: InjectedEvents
    /// 这一下按在哪块范围里：之后的拖动、抬起跟着这一下走，手指滑出范围也一样
    private var pressed: TouchRegion?

    init(regions: OSAllocatedUnfairLock<[TouchRegion]>, injectors: [InjectedEventSource],
         closeWindow: @escaping @Sendable (UInt32) -> Void,
         setSidebar: @escaping @Sendable (UInt32, Bool) -> Void) {
        self.regions = regions
        injected = InjectedEvents(injectors: injectors)
        self.closeWindow = closeWindow
        self.setSidebar = setSidebar
    }

    func start() -> Bool {
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [self] in
            let ok = installTap()
            if ok { runLoop = CFRunLoopGetCurrent() }
            ready.signal()
            if ok { CFRunLoopRun() }
        }
        thread.name = "com.zephyr4123.snug.touch"
        thread.qualityOfService = .userInteractive
        thread.start()
        // 建监听是同步的、很快，不设超时：设了超时反而会在超时后留下一个关不掉的监听。
        // signal / wait 也保证监听线程对 runLoop 的写入在这里可见
        ready.wait()
        return runLoop != nil
    }

    func stop() {
        guard let runLoop else { return }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) { [self] in
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: false)
                CFMachPortInvalidate(tap)
            }
            tap = nil
            stopCoasting()
            heldPress = nil
            CFRunLoopStop(CFRunLoopGetCurrent())
        }
        CFRunLoopWakeUp(runLoop)
    }

    private func installTap() -> Bool {
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: TouchEvents.mask, callback: Self.callback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        self.tap = tap
        CFRunLoopAddSource(CFRunLoopGetCurrent(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private static let callback: CGEventTapCallBack = { _, type, event, info in
        guard let info else { return Unmanaged.passUnretained(event) }
        return Unmanaged<TapSession>.fromOpaque(info).takeUnretainedValue().handle(type, event)
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            Log.warn("手势翻译的事件监听被系统停用（\(type == .tapDisabledByTimeout ? "回调超时" : "用户输入")），已重新开启")
            return pass
        }
        guard let kind = TouchEvents.kind(of: type), !TouchEvents.isReplay(event), injected.contains(event) else { return pass }

        let input = TouchInput(kind, at: event.location, time: ProcessInfo.processInfo.systemUptime)
        if kind == .press { pressed = regions.withLock { $0 }.first { $0.frame.contains(event.location) } }
        let region = pressed
        let response = translator.handle(input, in: region)
        if kind == .press, !response.passOriginal { heldPress = event.copy() }
        response.commands.forEach { perform($0, current: event, region: region) }
        if kind == .release { heldPress = nil }
        if translator.isCoasting { startCoasting() }
        return response.passOriginal ? pass : nil
    }

    private func perform(_ command: TouchCommand, current: CGEvent, region: TouchRegion?) {
        switch command {
        case .replayPress:
            TouchEvents.post(heldPress)
            heldPress = nil
        case .replayCurrent:
            TouchEvents.post(current.copy())
        case .rightClick(let point):
            TouchEvents.rightClick(at: point).forEach(TouchEvents.post)
        case .scroll(let step):
            TouchEvents.post(TouchEvents.scroll(step))
        case .closeWindow(let point):
            // 按钮位置是铺好时读的：点下去这一刻再问一次窗口服务器（不经过 App，很快），对不上就照常点
            if let button = region?.closeButton, button.isFrontmost(at: point, onScreen: Self.onScreen()) {
                closeWindow(button.window)
            } else {
                Log.info("点在屏上那个窗口原来的关闭按钮处，但那里已经不是它的关闭按钮（挪走、被盖住或全屏了），照常点击")
                perform(.replayPress, current: current, region: region)
                perform(.replayCurrent, current: current, region: region)
            }
        case .showSidebar, .hideSidebar:
            if let window = region?.sidebarSwipe?.window {
                let open = command == .showSidebar
                Log.info("Codex 横向滑动达到阈值：\(open ? "展开" : "关闭")侧边栏（窗口 \(window)）")
                setSidebar(window, open)
            } else {
                Log.warn("Codex 横向滑动已达到阈值，但手势范围里没有目标窗口")
            }
        }
    }

    /// 窗口服务器里此刻在屏上的窗口，从前到后
    private static func onScreen() -> [(id: UInt32, frame: CGRect)] {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        return (list ?? []).compactMap { info in
            guard let id = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return nil }
            return (id, frame)
        }
    }

    /// 惯性：在监听线程的 run loop 上按 60fps 走，走完自己停
    private func startCoasting() {
        guard coastTimer == nil else { return }
        let timer = CFRunLoopTimerCreateWithHandler(nil, CFAbsoluteTimeGetCurrent(), 1 / Momentum.frameRate, 0, 0) { [self] _ in
            if let step = translator.momentumFrame() { TouchEvents.post(TouchEvents.scroll(step)) }
            if !translator.isCoasting { stopCoasting() }
        }
        coastTimer = timer
        CFRunLoopAddTimer(CFRunLoopGetCurrent(), timer, .commonModes)
    }

    private func stopCoasting() {
        guard let timer = coastTimer else { return }
        CFRunLoopTimerInvalidate(timer)
        coastTimer = nil
    }
}
