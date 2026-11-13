// 窗口的身份与列表。窗口用「进程号 + 系统窗口编号」认（WindowKey）：编号在本次登录内唯一，
// 不会像辅助功能的窗口对象那样过期，也能写进还原记录，崩溃重启后照样找得到
import CoreGraphics
import Foundation

public struct WindowKey: Hashable, Codable, Sendable, CustomStringConvertible {
    public let pid: Int32
    /// CGWindowID
    public let id: UInt32

    public init(pid: Int32, id: UInt32) {
        self.pid = pid
        self.id = id
    }

    public var description: String { "\(pid)/\(id)" }
}

/// 窗口列表里的一张卡片
public struct WindowInfo: Equatable, Identifiable, Sendable {
    public let key: WindowKey
    public let app: String
    public let bundleID: String?
    public let title: String

    public init(key: WindowKey, app: String, bundleID: String?, title: String) {
        self.key = key
        self.app = app
        self.bundleID = bundleID
        self.title = title
    }

    public var id: WindowKey { key }
    /// 日志里用：App 名 +「标题前 30 个字」
    public var label: String { title.isEmpty ? app : "\(app)「\(title.prefix(30))」" }
}

public enum WindowList {
    /// 不出现在列表里的 App：UU远程 自己（把遥控器放到手机屏上没有意义）
    public static let excludedBundles: Set<String> = [UURemote.bundleID]

    /// 按前后层次排：最近用过的在前，和 iPhone 的多任务界面一样。
    /// frontToBack 是屏上窗口从前到后的编号；不在里面的（别的桌面上的）排最后，彼此保持原顺序
    public static func ordered(_ windows: [WindowInfo], frontToBack: [UInt32]) -> [WindowInfo] {
        let rank = Dictionary(frontToBack.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return windows
            .filter { !excludedBundles.contains($0.bundleID ?? "") }
            .enumerated()
            .sorted { (rank[$0.element.key.id] ?? Int.max, $0.offset) < (rank[$1.element.key.id] ?? Int.max, $1.offset) }
            .map(\.element)
    }
}

extension CGRect {
    /// 两个框在 2 点以内算对上（App 会把尺寸取整，跨屏还会差一两点）
    public func matches(_ other: CGRect, tolerance: CGFloat = 2) -> Bool {
        abs(minX - other.minX) < tolerance && abs(minY - other.minY) < tolerance
            && abs(width - other.width) < tolerance && abs(height - other.height) < tolerance
    }

    /// 日志里用：(x,y 宽x高)
    public var short: String { "(\(Int(minX)),\(Int(minY)) \(Int(width))x\(Int(height)))" }
}
