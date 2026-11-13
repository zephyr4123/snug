// 通过辅助功能接口读 UU远程 主界面：「全部设备」列表、「本机被控中」表格里的控制端，以及点菜单栏里的「显示主界面」。
// AX 调用会阻塞（UU 卡顿时每次最多等 1 秒），所以这里的函数都是同步的，只在后台队列调用，绝不在主线程。
// 进程号由调用方在主线程查好传进来，后台只碰 AX，不碰 AppKit
import ApplicationServices
import SnugCore

enum UUAccessibility {
    static let bundleID = "com.netease.uuremote"
    /// AX 树有环，按对象去重之外再限制深度和节点数；超限按「读不到」处理，不拿半截结果当真
    static let maxDepth = 25
    static let maxNodes = 2048

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// 「本机被控中」表格里的控制端名称。主窗口读不到返回 nil，明确无人控制返回 []
    static func readControllers(pid: pid_t) -> [String]? {
        guard let all = flattenWindows(pid: pid) else { return nil }
        var names: [String] = []
        for row in all where role(row) == kAXRowRole {
            var inner: [AXUIElement] = []
            var seen = Set<AXUIElement>()
            guard flatten(row, depth: 0, into: &inner, seen: &seen) else { return nil }
            let texts = inner.filter { role($0) == kAXStaticTextRole }.compactMap(value)
            // 只认带「远程控制」标记的行，别的表格不算连入
            guard texts.contains("远程控制") else { continue }
            if let n = texts.first(where: { $0 != "远程控制" && !$0.hasPrefix("连接时长") && !$0.isEmpty }), !names.contains(n) {
                names.append(n)
            }
        }
        return names
    }

    /// 「全部设备」列表。主窗口读不到返回 nil。
    /// 结构：分组标题（电脑 / 手机/平板）→ 32 号设备图标 + 设备名 [+「本机」]
    static func readDevices(pid: pid_t) -> [UUDevice]? {
        guard let all = flattenWindows(pid: pid) else { return nil }
        var parser = DeviceListParser()
        for el in all {
            switch role(el) {
            case kAXImageRole: parser.image(description: attr(el, kAXDescriptionAttribute) as? String ?? "", y: positionY(el))
            case kAXStaticTextRole: value(el).map { parser.text($0) }
            default: break
            }
        }
        return parser.devices
    }

    static func hasMainWindow(pid: pid_t) -> Bool { !windows(pid: pid).isEmpty }

    /// 点 UU 菜单栏图标里的「显示主界面」
    @discardableResult
    static func showMainWindow(pid: pid_t) -> Bool {
        let app = appElement(pid)
        guard let bar = attr(app, kAXExtrasMenuBarAttribute), CFGetTypeID(bar) == AXUIElementGetTypeID() else { return false }
        var all: [AXUIElement] = []
        var seen = Set<AXUIElement>()
        _ = flatten(bar as! AXUIElement, depth: 0, into: &all, seen: &seen)
        guard let item = all.first(where: { (attr($0, kAXIdentifierAttribute) as? String) == "showWindow" }) else { return false }
        return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
    }

    // MARK: AX 基础

    private static func appElement(_ pid: pid_t) -> AXUIElement {
        let ax = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(ax, 1.0)
        return ax
    }

    private static func attr(_ el: AXUIElement, _ name: String) -> AnyObject? {
        var v: AnyObject?
        return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
    }

    private static func role(_ el: AXUIElement) -> String? { attr(el, kAXRoleAttribute) as? String }
    private static func value(_ el: AXUIElement) -> String? { attr(el, kAXValueAttribute) as? String }

    private static func positionY(_ el: AXUIElement) -> Double {
        var pt = CGPoint.zero
        if let v = attr(el, kAXPositionAttribute), CFGetTypeID(v) == AXValueGetTypeID() {
            AXValueGetValue(v as! AXValue, .cgPoint, &pt)
        }
        return pt.y
    }

    /// 窗口列表之外再读主窗口和焦点窗口：别的 App 占着全屏 Space 时，UU 的 AXWindows 可能是空的，
    /// 主窗口引用却还有效。按 AX 对象去重，不激活 UU、不切 Space（思路来自社区 PR #10，作者 Rongzheng Liu）
    private static func windows(pid: pid_t) -> [AXUIElement] {
        let app = appElement(pid)
        var result = (attr(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []
        for key in [kAXMainWindowAttribute, kAXFocusedWindowAttribute] {
            guard let raw = attr(app, key), CFGetTypeID(raw) == AXUIElementGetTypeID() else { continue }
            let window = raw as! AXUIElement
            guard role(window) == kAXWindowRole, !result.contains(where: { CFEqual($0, window) }) else { continue }
            result.append(window)
        }
        return result
    }

    /// 所有窗口的节点；没有窗口或超出上限时返回 nil
    private static func flattenWindows(pid: pid_t) -> [AXUIElement]? {
        let wins = windows(pid: pid)
        guard !wins.isEmpty else { return nil }
        var all: [AXUIElement] = []
        var seen = Set<AXUIElement>()
        for w in wins {
            guard flatten(w, depth: 0, into: &all, seen: &seen) else { return nil }
        }
        return all
    }

    /// 先序遍历，按对象去重；超过深度或节点上限返回 false
    private static func flatten(_ node: AXUIElement, depth: Int, into out: inout [AXUIElement], seen: inout Set<AXUIElement>) -> Bool {
        guard !seen.contains(node) else { return true }
        guard depth < maxDepth, out.count < maxNodes else { return false }
        seen.insert(node)
        out.append(node)
        for child in (attr(node, kAXChildrenAttribute) as? [AXUIElement]) ?? [] {
            guard flatten(child, depth: depth + 1, into: &out, seen: &seen) else { return false }
        }
        return true
    }
}

/// 按 AX 先序把「全部设备」页拼成设备列表
private struct DeviceListParser {
    private var group: Bool?          // true = 电脑组
    private var pendingIcon = false
    private var pendingPlatform = ""
    private var pendingY = 0.0
    private var ys: [String: Double] = [:]
    private var result: [UUDevice] = []

    mutating func image(description d: String, y: Double) {
        pendingIcon = d.hasPrefix("icon device") && d.contains(" 32")
        guard pendingIcon else { return }
        pendingPlatform = d.split(separator: " ").dropFirst(2).first.map(String.init) ?? ""
        pendingY = y
    }

    mutating func text(_ raw: String) {
        let v = raw.trimmingCharacters(in: .whitespaces)
        guard !v.isEmpty else { return }
        if v == "电脑" { group = true; pendingIcon = false }
        else if v == "手机/平板" { group = false; pendingIcon = false }
        else if v == "本机", let last = result.popLast() {
            result.append(UUDevice(name: last.name, isComputerGroup: last.isComputerGroup, isSelf: true, platform: last.platform))
        } else if pendingIcon, let g = group {
            if !result.contains(where: { $0.name == v }) {
                result.append(UUDevice(name: v, isComputerGroup: g, isSelf: false, platform: pendingPlatform))
                ys[v] = pendingY
            }
            pendingIcon = false
        }
    }

    /// AX 顺序与界面相反，按图标的纵坐标排回 UU 的显示顺序
    var devices: [UUDevice] {
        result.enumerated()
            .sorted { (ys[$0.element.name] ?? 0, $0.offset) < (ys[$1.element.name] ?? 0, $1.offset) }
            .map(\.element)
    }
}
