// 控制端表格：解释 UU 主窗口里每一行的文字。AX 遍历在 App 层的 UUAccessibility，这里只认文字，所以能单独测。
// UU 只在被控时才显示「本机被控中」这张表，没有「无人」的空态：没被控时界面上什么都不显示，
// 首页、错误页的行，以及远程协助、副屏模式的行，也都不是这里要找的控制端。
// 所以只有认出控制端才算证据，没认出不等于没人（issue #1：主窗口停在首页时，正常远程 60 秒后被误判断开）
import Foundation

public enum ControllerTable: Equatable, Sendable, CustomStringConvertible {
    /// 没授权、UU 没在运行、没有窗口、遍历超限、读得太慢
    case unreadable
    /// 窗口读得到，但没认出控制端行
    case unrecognized
    /// 认出的控制端名称：按表格里的顺序、去重，不为空
    case shown([String])

    /// 控制端行带的连接方式。只认「远程控制」，远程协助、副屏模式的行不算
    static let controlMark = "远程控制"
    /// 控制端行里的连接时长，比如「连接时长 00:10」，不是名字
    static let durationPrefix = "连接时长"

    /// rows：每一行里的全部静态文字，按界面上的顺序
    public init(rows: [[String]]) {
        var names: [String] = []
        for texts in rows where texts.contains(Self.controlMark) {
            let name = texts.first { $0 != Self.controlMark && !$0.hasPrefix(Self.durationPrefix) && !$0.isEmpty }
            if let name, !names.contains(name) { names.append(name) }
        }
        self = names.isEmpty ? .unrecognized : .shown(names)
    }

    /// 认出的控制端；读不到、没认出时为空
    public var names: [String] {
        if case .shown(let names) = self { names } else { [] }
    }

    public var description: String {
        switch self {
        case .unreadable: "读不到"
        case .unrecognized: "未识别"
        case .shown(let names): names.joined(separator: ",")
        }
    }
}
