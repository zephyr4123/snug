// 手势翻译的系统部分：一个事件监听，只接管 UURemoteServer 发来、在手机屏里按下的鼠标左键，
// 交给 TouchTranslator 判断，再照它说的补发点击、右键或滚动。本机的触控板、鼠标一律不碰。
// 跑在独立线程上：主线程会被建屏、搬窗口卡住，监听回调一慢，系统会让全机的鼠标跟着卡。
// 补发的事件打上记号：拷贝出来的事件保留 UU 的进程号，不打记号会被自己再接管一次，来回打转
import CoreGraphics
import Darwin
import Foundation
import os
import SnugCore

public final class TouchTap: @unchecked Sendable {
    /// UU 在 Mac 上注入事件的进程
    static let sourceProcess = "UURemoteServer"
    /// eventSourceUserData 里的记号（'SNUG'）
    static let marker: Int64 = 0x534E_5547

    /// 手机屏的范围（CGEvent 坐标）。主线程写，监听线程读
    private let region = OSAllocatedUnfairLock<CGRect?>(initialState: nil)
    /// 监听线程的 run loop，停的时候要往里投递。CFRunLoop 不是 Sendable，用普通锁护着
    private let loopLock = NSLock()
    private var loop: CFRunLoop?

    // 以下只在监听线程上访问
    private var tap: CFMachPort?
    private var translator = TouchTranslator()
    private var heldPress: CGEvent?
    private var coastTimer: CFRunLoopTimer?
    private var isUU: [pid_t: Bool] = [:]

    public init() {}

    public var isRunning: Bool { runLoop != nil }

    private var runLoop: CFRunLoop? {
        get { loopLock.withLock { loop } }
        set { loopLock.withLock { loop = newValue } }
    }

    public func setRegion(_ rect: CGRect?) { region.withLock { $0 = rect } }

    /// 起监听线程，等它报告监听建没建成（没有辅助功能权限时建不成）
    @discardableResult
    public func start() -> Bool {
        guard !isRunning else { return true }
        let ready = DispatchSemaphore(value: 0)
        let started = OSAllocatedUnfairLock(initialState: false)
        let thread = Thread { [self] in
            let ok = installTap()
            started.withLock { $0 = ok }
            ready.signal()
            if ok { CFRunLoopRun() }
        }
        thread.name = "com.zephyr4123.snug.touch"
        thread.qualityOfService = .userInteractive
        thread.start()
        _ = ready.wait(timeout: .now() + 2)
        let ok = started.withLock { $0 }
        if ok {
            Log.info("手势翻译已开启（只接管 \(Self.sourceProcess) 发来、在手机屏里的操作）")
        } else {
            Log.error("手势翻译开不起来：建事件监听失败（多半是没有辅助功能权限）")
        }
        return ok
    }

    public func stop() {
        guard let runLoop else { return }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) { [self] in
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: false)
                CFMachPortInvalidate(tap)
            }
            tap = nil
            stopCoasting()
            heldPress = nil
            translator = TouchTranslator()
            isUU = [:]
            self.runLoop = nil
            CFRunLoopStop(CFRunLoopGetCurrent())
        }
        CFRunLoopWakeUp(runLoop)
        Log.info("手势翻译已关闭")
    }

    // MARK: 监听线程

    private func installTap() -> Bool {
        let mask = [CGEventType.leftMouseDown, .leftMouseDragged, .leftMouseUp].reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: Self.callback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        self.tap = tap
        CFRunLoopAddSource(CFRunLoopGetCurrent(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        runLoop = CFRunLoopGetCurrent()
        return true
    }

    private static let callback: CGEventTapCallBack = { _, type, event, info in
        guard let info else { return Unmanaged.passUnretained(event) }
        return Unmanaged<TouchTap>.fromOpaque(info).takeUnretainedValue().handle(type, event)
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            Log.warn("手势翻译的事件监听被系统停用（\(type == .tapDisabledByTimeout ? "回调超时" : "用户输入")），已重新开启")
            return pass
        }
        let kind: TouchInput.Kind
        switch type {
        case .leftMouseDown: kind = .press
        case .leftMouseDragged: kind = .drag
        case .leftMouseUp: kind = .release
        default: return pass
        }
        guard event.getIntegerValueField(.eventSourceUserData) != Self.marker, fromUU(event) else { return pass }

        let inside = region.withLock { $0 }?.contains(event.location) ?? false
        let input = TouchInput(kind, at: event.location, time: ProcessInfo.processInfo.systemUptime)
        let response = translator.handle(input, insidePhoneScreen: inside)
        if kind == .press, !response.passOriginal { heldPress = event.copy() }
        response.commands.forEach { perform($0, current: event) }
        if kind == .release { heldPress = nil }
        if translator.isCoasting { startCoasting() }
        return response.passOriginal ? pass : nil
    }

    private func perform(_ command: TouchCommand, current: CGEvent) {
        switch command {
        case .replayPress:
            post(heldPress)
            heldPress = nil
        case .replayCurrent:
            post(current.copy())
        case .rightClick(let point):
            for type in [CGEventType.rightMouseDown, .rightMouseUp] {
                let click = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .right)
                click?.setIntegerValueField(.mouseEventClickState, value: 1)
                post(click)
            }
        case .scroll(let step):
            post(Self.scrollEvent(step))
        }
    }

    private func post(_ event: CGEvent?) {
        guard let event else { return }
        event.setIntegerValueField(.eventSourceUserData, value: Self.marker)
        event.post(tap: .cgSessionEventTap)
    }

    /// 带相位的像素滚动：App 看到的和触控板两指滑动一样
    private static func scrollEvent(_ s: ScrollStep) -> CGEvent? {
        guard let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                              wheel1: s.pixelsY, wheel2: s.pixelsX, wheel3: 0) else { return nil }
        e.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        e.setIntegerValueField(.scrollWheelEventScrollPhase, value: s.phase.rawValue)
        e.setIntegerValueField(.scrollWheelEventMomentumPhase, value: s.momentum.rawValue)
        e.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: s.deltaY)
        e.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: s.deltaX)
        e.location = s.location
        return e
    }

    /// 惯性：在监听线程的 run loop 上按 60fps 走，走完自己停
    private func startCoasting() {
        guard coastTimer == nil else { return }
        let timer = CFRunLoopTimerCreateWithHandler(nil, CFAbsoluteTimeGetCurrent(), 1 / Momentum.frameRate, 0, 0) { [self] _ in
            if let step = translator.momentumFrame() { post(Self.scrollEvent(step)) }
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

    /// 事件是不是 UURemoteServer 注入的：按来源进程号查可执行文件名，按进程号缓存
    private func fromUU(_ event: CGEvent) -> Bool {
        let pid = pid_t(event.getIntegerValueField(.eventSourceUnixProcessID))
        guard pid > 0 else { return false }
        if let known = isUU[pid] { return known }
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let length = Int(proc_pidpath(pid, &buffer, UInt32(buffer.count)))
        let path = length > 0 ? String(decoding: buffer.prefix(length).map { UInt8(bitPattern: $0) }, as: UTF8.self) : ""
        let match = (path as NSString).lastPathComponent == Self.sourceProcess
        isUU[pid] = match
        return match
    }
}
