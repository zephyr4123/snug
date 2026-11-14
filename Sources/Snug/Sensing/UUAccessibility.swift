// 通过辅助功能接口读 UU远程 窗口里表格每一行的文字，交给 ControllerTable 认控制端。只读，不点 UU 的任何东西，
// 不为了读表格把 UU 的窗口弹出来或切页面：读不到、没认出都照常远程，只是少了一路在场证据和控制端名字（读不到按手机处理）。
// 主窗口最小化也读得到；没有窗口时读不到。
// AX 调用会阻塞（UU 卡顿时每次最多等 1 秒），所以这里的函数都是同步的，只在后台队列调用，绝不在主线程。
// 进程号由调用方在主线程查好传进来，后台只碰 AX，不碰 AppKit
import ApplicationServices
import SnugCore
import SnugSystem

enum UUAccessibility {
    /// AX 树有环，按对象去重之外再限制深度和节点数；超限按「读不到」处理，不拿半截结果当真
    static let maxDepth = 25
    static let maxNodes = 2048

    /// UU 所有窗口里每个表格行的静态文字，按界面顺序。没有窗口或超出上限时返回 nil
    static func rows(pid: pid_t) -> [[String]]? {
        guard let all = flattenWindows(pid: pid) else { return nil }
        var rows: [[String]] = []
        for row in all where role(row) == kAXRowRole {
            var inner: [AXUIElement] = []
            var seen = Set<AXUIElement>()
            guard flatten(row, depth: 0, into: &inner, seen: &seen) else { return nil }
            rows.append(inner.filter { role($0) == kAXStaticTextRole }.compactMap(value))
        }
        return rows
    }

    // MARK: AX 基础（薄封装在 SnugSystem 的 AX）

    private static func role(_ el: AXUIElement) -> String? { AX.string(el, kAXRoleAttribute) }
    private static func value(_ el: AXUIElement) -> String? { AX.string(el, kAXValueAttribute) }

    /// 窗口列表之外再读主窗口和焦点窗口：别的 App 占着全屏 Space 时，UU 的 AXWindows 可能是空的，
    /// 主窗口引用却还有效。按 AX 对象去重，不激活 UU、不切 Space（思路来自社区 PR #10，作者 Rongzheng Liu）
    private static func windows(pid: pid_t) -> [AXUIElement] {
        let app = AX.application(pid)
        var result = (AX.attribute(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []
        for key in [kAXMainWindowAttribute, kAXFocusedWindowAttribute] {
            guard let raw = AX.attribute(app, key), CFGetTypeID(raw) == AXUIElementGetTypeID() else { continue }
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
        for child in (AX.attribute(node, kAXChildrenAttribute) as? [AXUIElement]) ?? [] {
            guard flatten(child, depth: depth + 1, into: &out, seen: &seen) else { return false }
        }
        return true
    }
}
