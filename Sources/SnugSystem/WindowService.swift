// 搬窗口、调字号：辅助功能接口 + 按 pid 投递的按键。
// 辅助功能的调用会阻塞（App 卡住时每次最多等 1 秒），全部放在自己的串行队列上做，主线程不等。
// 窗口按「进程号 + 系统窗口编号」找：每次用时现找，不留辅助功能对象（App 重建窗口后旧对象会失效）。
// 不管窗口在哪块屏、哪个桌面空间、是否全屏或最小化都找得到（见 AX.allWindows）；
// 窗口在不在问窗口服务器（exists），不经过 App：App 卡住时辅助功能读不到，不能当成窗口关了
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
        // 窗口服务器知道每个窗口（别的桌面空间、最小化的也在），不用等 App 响应，也不要权限
        guard let info = CGWindowListCopyWindowInfo([.optionIncludingWindow], window.id) as? [[String: Any]],
              let owner = (info.first?[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value else { return false }
        return owner == window.pid
    }

    public func look(_ window: WindowKey) async -> WindowLook? {
        await run {
            guard let element = AX.element(for: window), let frame = AX.frame(element) else { return nil }
            return WindowLook(frame: frame, fullScreen: AX.flag(element, AX.fullScreen), minimized: AX.flag(element, kAXMinimizedAttribute))
        }
    }

    public func move(_ window: WindowKey, to frame: CGRect) async -> CGRect? {
        await run {
            guard let element = AX.element(for: window) else { return nil }
            return Self.move(element, to: frame)
        }
    }

    public func setFullScreen(_ window: WindowKey, _ on: Bool) async {
        await run {
            guard let element = AX.element(for: window) else { return }
            AX.set(element, AX.fullScreen, on as CFBoolean)
            for _ in 0..<20 where AX.flag(element, AX.fullScreen) != on { Thread.sleep(forTimeInterval: 0.25) }
            // 等全屏动画走完，不然紧接着的挪动会被动画盖掉
            Thread.sleep(forTimeInterval: 1.2)
        }
    }

    public func setMinimized(_ window: WindowKey, _ on: Bool) async {
        await run {
            guard let element = AX.element(for: window) else { return }
            Self.setMinimized(element, on)
        }
    }

    public func focus(_ window: WindowKey) async {
        await run {
            guard let element = AX.element(for: window) else { return }
            if AX.flag(element, kAXMinimizedAttribute) { Self.setMinimized(element, false) }
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
                for element in AX.visibleWindows(pid: app.pid) where AX.isStandard(element) && !AX.flag(element, kAXMinimizedAttribute) {
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
                Log.info("系统挪了 pid \(window.pid) 的窗口 \(now.short)，已放回 \(saved.short)"
                         + (got.map { $0.matches(saved) } == true ? "" : "（没对上，现在 \(got?.short ?? "?")）"))
            }
        }
    }

    // MARK: 窗口列表（手机屏上的卡片）

    /// 所有可以放上手机屏的窗口：不管在哪块屏、哪个桌面空间，全屏、最小化的也算。最近用过的在前
    public func list() async -> [WindowInfo] {
        let apps = await Self.regularApps()
        return await run {
            var windows: [WindowInfo] = []
            for app in apps {
                for element in AX.allWindows(pid: app.pid) where AX.isStandard(element) {
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

    /// 设好后等它真的变过去，再等动画走完
    private static func setMinimized(_ element: AXUIElement, _ on: Bool) {
        AX.set(element, kAXMinimizedAttribute, on as CFBoolean)
        for _ in 0..<12 where AX.flag(element, kAXMinimizedAttribute) != on { Thread.sleep(forTimeInterval: 0.25) }
        Thread.sleep(forTimeInterval: 0.5)
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
}

/// 辅助功能接口的薄封装
public enum AX {
    static let fullScreen = "AXFullScreen"
    /// 远程令牌最多试到这个元素编号（AltTab 也是试前 1000 个）
    static let remoteScanLimit: UInt64 = 1000

    public static var isTrusted: Bool { AXIsProcessTrusted() }

    /// App 的辅助功能对象。App 卡住时每次调用最多等 1 秒
    public static func application(_ pid: pid_t) -> AXUIElement {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1.0)
        return app
    }

    public static func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    public static func string(_ element: AXUIElement, _ name: String) -> String? { attribute(element, name) as? String }

    static func flag(_ element: AXUIElement, _ name: String) -> Bool { (attribute(element, name) as? Bool) == true }

    @discardableResult
    static func set(_ element: AXUIElement, _ name: String, _ value: AnyObject) -> Bool {
        AXUIElementSetAttributeValue(element, name as CFString, value) == .success
    }

    /// 标准窗口（不含面板、对话框）
    static func isStandard(_ element: AXUIElement) -> Bool { string(element, kAXSubroleAttribute) == kAXStandardWindowSubrole }

    /// 当前显示着的桌面空间里的窗口（系统给的窗口列表，含最小化的）
    public static func visibleWindows(pid: pid_t) -> [AXUIElement] {
        (attribute(application(pid), kAXWindowsAttribute) as? [AXUIElement]) ?? []
    }

    /// App 所有的窗口：不管在哪块屏、哪个桌面空间，全屏、最小化的也算。
    /// 系统给的窗口列表只含当前显示着的空间（别的 App 全屏占着时，其余窗口全不在里面），
    /// 其余的用远程令牌按元素编号逐个构造辅助功能对象找出来（AltTab 公开的做法，令牌 = pid + 0 + "coco" + 元素编号）
    public static func allWindows(pid: pid_t) -> [AXUIElement] {
        guard var windows = respondingWindows(pid: pid) else { return [] }
        var seen = Set(windows.compactMap(windowID))
        for element in remoteWindows(pid: pid) {
            guard let id = windowID(element), seen.insert(id).inserted else { continue }
            windows.append(element)
        }
        return windows
    }

    static func element(for window: WindowKey) -> AXUIElement? {
        guard let visible = respondingWindows(pid: window.pid) else { return nil }
        if let hit = visible.first(where: { windowID($0) == window.id }) { return hit }
        return remoteWindows(pid: window.pid).first { windowID($0) == window.id }
    }

    /// 系统给的窗口列表；App 没响应（或不支持辅助功能）返回 nil。
    /// 这时不能再用远程令牌逐个去试：每个编号都要等一次超时，一千个编号就是好几分钟
    private static func respondingWindows(pid: pid_t) -> [AXUIElement]? {
        var value: AnyObject?
        switch AXUIElementCopyAttributeValue(application(pid), kAXWindowsAttribute as CFString, &value) {
        case .success: return (value as? [AXUIElement]) ?? []
        case .noValue: return []
        default: return nil
        }
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

    static func setPosition(_ element: AXUIElement, _ point: CGPoint) {
        var p = point
        if let value = AXValueCreate(.cgPoint, &p) { set(element, kAXPositionAttribute, value) }
    }

    static func setSize(_ element: AXUIElement, _ size: CGSize) {
        var s = size
        if let value = AXValueCreate(.cgSize, &s) { set(element, kAXSizeAttribute, value) }
    }

    /// 用远程令牌找出的窗口对象（含当前空间里的；调用方按窗口编号去重）
    private static func remoteWindows(pid: pid_t) -> [AXUIElement] {
        var token = Data(count: 20)
        token.replaceSubrange(0..<4, with: withUnsafeBytes(of: pid) { Data($0) })
        token.replaceSubrange(8..<12, with: withUnsafeBytes(of: Int32(0x636F_636F)) { Data($0) })
        var found: [AXUIElement] = []
        for elementID in UInt64(0)..<remoteScanLimit {
            token.replaceSubrange(12..<20, with: withUnsafeBytes(of: elementID) { Data($0) })
            guard let element = _AXUIElementCreateWithRemoteToken(token as CFData)?.takeRetainedValue() else { continue }
            AXUIElementSetMessagingTimeout(element, 0.25)
            var role: AnyObject?
            let result = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
            // 不存在的编号回 invalidUIElement（实测）；回 cannotComplete 是 App 中途卡住了，不再往下试
            if result == .cannotComplete { break }
            guard result == .success, role as? String == kAXWindowRole else { continue }
            found.append(element)
        }
        return found
    }
}

/// 辅助功能窗口对象 → 系统窗口编号（私有接口，yabai、Rectangle、AltTab 都在用）
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

/// 按令牌构造另一个进程里的辅助功能对象（私有接口，AltTab 用它找别的桌面空间里的窗口）
@_silgen_name("_AXUIElementCreateWithRemoteToken")
private func _AXUIElementCreateWithRemoteToken(_ token: CFData) -> Unmanaged<AXUIElement>?
