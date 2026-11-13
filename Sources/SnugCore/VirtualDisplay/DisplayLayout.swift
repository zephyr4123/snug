// 物理屏布局快照（layout.json）：每块物理屏的原点与显示模式。
// 会话第一次改拓扑（建虚拟屏）之前采集，还原时先恢复模式、再恢复原点，原点恢复成功才删记录（修 B9）
import Foundation

public struct DisplayModeInfo: Codable, Equatable, Sendable {
    /// CGDisplayModeGetIODisplayModeID：同一块屏上模式的稳定编号
    public var ioDisplayModeID: Int32
    public var width: Int
    public var height: Int
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var refreshRate: Double

    public init(ioDisplayModeID: Int32, width: Int, height: Int, pixelWidth: Int, pixelHeight: Int, refreshRate: Double) {
        self.ioDisplayModeID = ioDisplayModeID
        self.width = width
        self.height = height
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.refreshRate = refreshRate
    }
}

public struct DisplayLayoutEntry: Codable, Equatable, Sendable {
    public var id: DisplayID
    public var originX: Int
    public var originY: Int
    /// 读不到当前模式时为 nil，只还原原点
    public var mode: DisplayModeInfo?

    public init(id: DisplayID, originX: Int, originY: Int, mode: DisplayModeInfo?) {
        self.id = id
        self.originX = originX
        self.originY = originY
        self.mode = mode
    }
}

public struct LayoutSnapshot: Codable, Equatable, Sendable {
    public var version = 1
    public var capturedAt: Date
    public var displays: [DisplayLayoutEntry]

    public init(capturedAt: Date, displays: [DisplayLayoutEntry]) {
        self.capturedAt = capturedAt
        self.displays = displays
    }
}

// 模式恢复的思路来自社区 PR #14（作者 bubble）：只还原原点会让分辨率停在系统默认值。
// 这里在它的基础上改了两点：先比 ioDisplayModeID（同尺寸同刷新率下可能有多个模式，例如色深不同），
// 当前模式已经对就跳过
public enum DisplayModeMatcher {
    /// 当前模式已经是保存的那个：跳过，不重设（重设可能多闪一次屏）
    public static func isSame(_ current: DisplayModeInfo, as saved: DisplayModeInfo) -> Bool {
        current.ioDisplayModeID == saved.ioDisplayModeID && sameShape(current, saved)
    }

    /// 在候选模式里找保存的那个，返回下标；找不到返回 nil（调用方退化成只还原原点）。
    /// 先找 ioDisplayModeID 相同且尺寸也对得上的（换过线、重新协商后编号可能指向别的模式，所以尺寸也要核）；
    /// 再找尺寸、像素、刷新率都对得上的
    public static func bestMatch(for saved: DisplayModeInfo, in candidates: [DisplayModeInfo]) -> Int? {
        candidates.firstIndex { isSame($0, as: saved) } ?? candidates.firstIndex { sameShape($0, saved) }
    }

    private static func sameShape(_ a: DisplayModeInfo, _ b: DisplayModeInfo) -> Bool {
        a.width == b.width && a.height == b.height && a.pixelWidth == b.pixelWidth && a.pixelHeight == b.pixelHeight
            && abs(a.refreshRate - b.refreshRate) < 0.5
    }
}
