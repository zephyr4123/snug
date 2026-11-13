// 辅助功能接口的薄封装：搬窗口（WindowService）和感知 UU（读控制端表格）共用。
// 超时：App 卡住时辅助功能的每次调用要等满超时，系统默认约 6 秒；Snug 把本进程的全局超时设成 1 秒（configureTimeout）。
// 两个私有接口（_AXUIElementGetWindow、_AXUIElementCreateWithRemoteToken）只在这个文件里用
import AppKit
import ApplicationServices
import SnugCore

public enum AX {
    static let fullScreen = "AXFullScreen"
    /// 远程令牌最多试到这个元素编号（AltTab 也是试前 1000 个）
    static let remoteScanLimit: UInt64 = 1000
    /// App 卡住时每次调用最多等这么久
    static let timeout: Float = 1
    /// 逐个试编号时每个编号最多等这么久（不存在的编号会立刻回错，等满的只有卡住的 App）
    static let probeTimeout: Float = 0.25

    public static var isTrusted: Bool { AXIsProcessTrusted() }

    /// 把本进程的全局超时设成 timeout。只对单个对象设只管那一个对象（头文件原话），
    /// 从 App 对象取回的窗口对象照样走系统默认的约 6 秒；启动时调一次
    public static func configureTimeout() {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), timeout)
    }

    public static func application(_ pid: pid_t) -> AXUIElement { AXUIElementCreateApplication(pid) }

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

    /// 提到最前并设成 App 的当前窗口：激活、发字号按键都要先做这一步（按键由 App 交给它的当前窗口）
    static func raise(_ element: AXUIElement) {
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        set(element, kAXMainAttribute, kCFBooleanTrue)
    }

    /// App 所有的窗口：不管在哪块屏、哪个桌面空间，全屏、最小化的也算。
    /// 系统给的窗口列表只含当前显示着的空间（别的 App 全屏占着时，其余窗口全不在里面），
    /// 其余的由 remote 给出（远程令牌试出来的，见 remoteWindows(pid:until:)）。App 没响应时不去要
    static func allWindows(pid: pid_t, remote: () -> [AXUIElement]) -> [AXUIElement] {
        guard var windows = respondingWindows(pid: pid) else { return [] }
        var seen = Set(windows.compactMap(windowID))
        for element in remote() {
            guard let id = windowID(element), seen.insert(id).inserted else { continue }
            windows.append(element)
        }
        return windows
    }

    static func element(for window: WindowKey) -> AXUIElement? {
        guard let visible = respondingWindows(pid: window.pid) else { return nil }
        if let hit = visible.first(where: { windowID($0) == window.id }) { return hit }
        return remoteWindows(pid: window.pid, until: window.id).windows.first { windowID($0) == window.id }
    }

    /// 当前显示着的桌面空间里的窗口（系统给的窗口列表，含最小化的）；App 没响应（或不支持辅助功能）返回 nil。
    /// 这时不能再用远程令牌逐个去试：每个编号都要等一次超时，一千个编号就是好几分钟
    static func respondingWindows(pid: pid_t) -> [AXUIElement]? {
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

    /// 用远程令牌按元素编号逐个构造辅助功能对象，找出 App 的窗口（AltTab 公开的做法，令牌 = pid + 0 + "coco" + 元素编号）。
    /// 含当前空间里的，调用方按窗口编号去重；给了 until 就找到那个窗口为止。
    /// complete 为 false：试到一半 App 卡住了，结果不全（不该拿去当缓存）
    static func remoteWindows(pid: pid_t, until wanted: UInt32? = nil) -> (windows: [AXUIElement], complete: Bool) {
        var token = Data(count: 20)
        token.replaceSubrange(0..<4, with: withUnsafeBytes(of: pid) { Data($0) })
        token.replaceSubrange(8..<12, with: withUnsafeBytes(of: Int32(0x636F_636F)) { Data($0) })
        var found: [AXUIElement] = []
        for elementID in UInt64(0)..<remoteScanLimit {
            token.replaceSubrange(12..<20, with: withUnsafeBytes(of: elementID) { Data($0) })
            guard let element = _AXUIElementCreateWithRemoteToken(token as CFData)?.takeRetainedValue() else { continue }
            AXUIElementSetMessagingTimeout(element, probeTimeout)
            var role: AnyObject?
            let result = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
            // 不存在的编号回 invalidUIElement（实测）；回 cannotComplete 是 App 中途卡住了，不再往下试
            if result == .cannotComplete { return (found, false) }
            guard result == .success, role as? String == kAXWindowRole else { continue }
            // 找到了就改回全局超时：拿去挪窗口、切全屏时，App 慢一点也不至于当成没响应
            AXUIElementSetMessagingTimeout(element, 0)
            found.append(element)
            if let wanted, windowID(element) == wanted { break }
        }
        return (found, true)
    }
}

/// 辅助功能窗口对象 → 系统窗口编号（私有接口，yabai、Rectangle、AltTab 都在用）
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

/// 按令牌构造另一个进程里的辅助功能对象（私有接口，AltTab 用它找别的桌面空间里的窗口）
@_silgen_name("_AXUIElementCreateWithRemoteToken")
private func _AXUIElementCreateWithRemoteToken(_ token: CFData) -> Unmanaged<AXUIElement>?
