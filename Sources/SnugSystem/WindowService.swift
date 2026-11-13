// 搬窗口、调字号：辅助功能接口 + 按 pid 投递的按键。
// 辅助功能的调用会阻塞（App 卡住时每次最多等 1 秒），全部放在自己的串行队列上做，主线程不等。
// 窗口按「进程号 + 系统窗口编号」找：每次用时现找，不留辅助功能对象（App 重建窗口后旧对象会失效）
import AppKit
import ApplicationServices
import SnugCore

public final class WindowService: WindowControl {
    /// 每次重试之间等的时间、最多试几次：跨屏改大小时 App 会按它以为的那块屏夹紧尺寸，刚加的屏 App 也可能还没认到
    static let retryDelay: TimeInterval = 0.25
    static let maxTries = 10
    /// kVK_ANSI_Equal、kVK_ANSI_Minus（不为两个常量引入 Carbon：它的 WindowKey 会和我们的重名）
    static let equalKey: CGKeyCode = 0x18
    static let minusKey: CGKeyCode = 0x1B

    private let queue = DispatchQueue(label: "com.zephyr4123.snug.windows", qos: .userInitiated)

    public init() {}

    // MARK: WindowControl

    public func exists(_ window: WindowKey) async -> Bool {
        await run { AX.element(for: window) != nil }
    }

    public func frame(of window: WindowKey) async -> CGRect? {
        await run { AX.element(for: window).flatMap(AX.frame) }
    }

    public func move(_ window: WindowKey, to frame: CGRect) async -> CGRect? {
        await run {
            guard let element = AX.element(for: window) else { return nil }
            return Self.move(element, to: frame)
        }
    }

    public func isFullScreen(_ window: WindowKey) async -> Bool {
        await run { AX.element(for: window).map(AX.isFullScreen) ?? false }
    }

    public func setFullScreen(_ window: WindowKey, _ on: Bool) async {
        await run {
            guard let element = AX.element(for: window) else { return }
            AX.set(element, AX.fullScreen, on as CFBoolean)
            for _ in 0..<20 where AX.isFullScreen(element) != on { Thread.sleep(forTimeInterval: 0.25) }
            // 等全屏动画走完，不然紧接着的挪动会被动画盖掉
            Thread.sleep(forTimeInterval: 1.2)
        }
    }

    public func focus(_ window: WindowKey) async {
        await run {
            guard let element = AX.element(for: window) else { return }
            AXUIElementPerformAction(element, kAXRaiseAction as CFString)
            AX.set(element, kAXMainAttribute, kCFBooleanTrue)
        }
        await MainActor.run {
            if NSRunningApplication(processIdentifier: window.pid)?.activate() == false {
                Log.warn("激活 pid \(window.pid) 没成功，键盘输入可能进不了这个窗口")
            }
        }
    }

    public func zoom(_ window: WindowKey, steps: Int) async -> Bool {
        await run {
            guard steps != 0 else { return true }
            guard let element = AX.element(for: window) else { return false }
            // 按键投给 App，App 交给它的当前窗口：先把这个窗口设成当前窗口
            AXUIElementPerformAction(element, kAXRaiseAction as CFString)
            AX.set(element, kAXMainAttribute, kCFBooleanTrue)
            let key = steps > 0 ? Self.equalKey : Self.minusKey
            for _ in 0..<abs(steps) {
                for down in [true, false] {
                    guard let event = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: down) else { continue }
                    event.flags = .maskCommand
                    event.postToPid(window.pid)
                }
                Thread.sleep(forTimeInterval: 0.08)
            }
            return true
        }
    }

    public func snapshot() async -> [WindowKey: CGRect] {
        let apps = await Self.regularApps()
        return await run {
            var frames: [WindowKey: CGRect] = [:]
            for app in apps {
                for element in AX.standardWindows(pid: app.pid) {
                    guard let id = AX.windowID(element), let frame = AX.frame(element) else { continue }
                    frames[WindowKey(pid: app.pid, id: id)] = frame
                }
            }
            return frames
        }
    }

    public func restore(_ snapshot: [WindowKey: CGRect], except: WindowKey?) async {
        await run {
            for (window, saved) in snapshot where window != except {
                guard let element = AX.element(for: window), let now = AX.frame(element), !now.matches(saved) else { continue }
                let got = Self.move(element, to: saved)
                Log.info("系统挪了 pid \(window.pid) 的窗口 \(Self.short(now))，已放回 \(Self.short(saved))"
                         + (got.map { $0.matches(saved) } == true ? "" : "（没对上，现在 \(got.map(Self.short) ?? "?")）"))
            }
        }
    }

    // MARK: 窗口列表（手机屏上的卡片）

    /// 所有可以放上手机屏的窗口，最近用过的在前
    public func list() async -> [WindowInfo] {
        let apps = await Self.regularApps()
        return await run {
            var windows: [WindowInfo] = []
            for app in apps {
                for element in AX.standardWindows(pid: app.pid) {
                    guard let id = AX.windowID(element) else { continue }
                    windows.append(WindowInfo(key: WindowKey(pid: app.pid, id: id), app: app.name, bundleID: app.bundleID,
                                              title: AX.string(element, kAXTitleAttribute) ?? ""))
                }
            }
            return WindowList.ordered(windows, frontToBack: Self.frontToBack())
        }
    }

    // MARK: 内部

    private func run<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work()) }
        }
    }

    /// 先改大小、再挪、再改大小，然后核对，对不上就重来
    private static func move(_ element: AXUIElement, to target: CGRect) -> CGRect? {
        var got: CGRect?
        for _ in 0..<maxTries {
            AX.setSize(element, target.size)
            AX.setPosition(element, target.origin)
            AX.setSize(element, target.size)
            Thread.sleep(forTimeInterval: retryDelay)
            got = AX.frame(element)
            if got?.matches(target) == true { break }
        }
        return got
    }

    private struct App: Sendable {
        let pid: pid_t
        let name: String
        let bundleID: String?
    }

    /// 普通 App（有 Dock 图标的），不含 Snug 自己
    private static func regularApps() async -> [App] {
        await MainActor.run {
            NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular && $0 != NSRunningApplication.current }
                .map { App(pid: $0.processIdentifier, name: $0.localizedName ?? "未命名", bundleID: $0.bundleIdentifier) }
        }
    }

    /// 屏上窗口从前到后的编号
    private static func frontToBack() -> [UInt32] {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        return (list ?? []).compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value }
    }

    private static func short(_ r: CGRect) -> String { "(\(Int(r.minX)),\(Int(r.minY)) \(Int(r.width))x\(Int(r.height)))" }
}

/// 辅助功能接口的薄封装
enum AX {
    static let fullScreen = "AXFullScreen"

    static func application(_ pid: pid_t) -> AXUIElement {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1.0)
        return app
    }

    static func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    static func string(_ element: AXUIElement, _ name: String) -> String? { attribute(element, name) as? String }

    @discardableResult
    static func set(_ element: AXUIElement, _ name: String, _ value: AnyObject) -> Bool {
        AXUIElementSetAttributeValue(element, name as CFString, value) == .success
    }

    /// 标准窗口（不含面板、对话框），最小化的不算
    static func standardWindows(pid: pid_t) -> [AXUIElement] {
        let windows = (attribute(application(pid), kAXWindowsAttribute) as? [AXUIElement]) ?? []
        return windows.filter {
            string($0, kAXSubroleAttribute) == kAXStandardWindowSubrole && (attribute($0, kAXMinimizedAttribute) as? Bool) != true
        }
    }

    static func element(for window: WindowKey) -> AXUIElement? {
        let windows = (attribute(application(window.pid), kAXWindowsAttribute) as? [AXUIElement]) ?? []
        return windows.first { windowID($0) == window.id }
    }

    static func windowID(_ element: AXUIElement) -> UInt32? {
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(element, &id) == .success && id != 0 ? id : nil
    }

    static func frame(_ element: AXUIElement) -> CGRect? {
        guard let p = attribute(element, kAXPositionAttribute), let s = attribute(element, kAXSizeAttribute),
              CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &origin), AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    static func isFullScreen(_ element: AXUIElement) -> Bool { (attribute(element, fullScreen) as? Bool) == true }

    static func setPosition(_ element: AXUIElement, _ point: CGPoint) {
        var p = point
        if let value = AXValueCreate(.cgPoint, &p) { set(element, kAXPositionAttribute, value) }
    }

    static func setSize(_ element: AXUIElement, _ size: CGSize) {
        var s = size
        if let value = AXValueCreate(.cgSize, &s) { set(element, kAXSizeAttribute, value) }
    }
}

/// 辅助功能窗口对象 → 系统窗口编号（私有接口，yabai、Rectangle、AltTab 都在用）
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError
