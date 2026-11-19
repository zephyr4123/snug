// 一块屏上那个窗口的还原记录（每块屏一份）：放上去之前写下原位，字号每改一次先记再改，放回原位才删。
// Snug 崩溃时 macOS 会自动撤掉 Snug 的屏，窗口被系统挪到别的屏上；下次启动按这份记录放回原处、字号缩回。
// 窗口在 Snug 之外没了（用户在手机上关掉、App 自己换了窗口）时，这份记录转成留下的账（LeftBehind），等它回来再还
import CoreGraphics
import Foundation

public struct PlacedRecord: Codable, Equatable, Sendable {
    public var window: WindowKey
    /// 提示里用（「Ghostty 无响应」）
    public var app: String
    /// 日志里用
    public var label: String
    /// 原位（辅助功能坐标：左上原点）
    public var original: CGRect
    /// 未设主屏时，记录原屏的原点。旧记录仍可按原来的全局坐标还原。
    var originalDisplay: DisplayAnchor?
    public var wasFullScreen: Bool
    public var wasMinimized: Bool
    /// 比原来放大了几级
    public var zoom: Int
    // 以下三项 2.4.2 加的，旧版写的记录里没有（读出来是 nil）：认出窗口在 Snug 之外没了以后又回来的就是它
    public var bundleID: String?
    public var title: String?
    /// Snug 最后把它铺成的样子。App 关窗时会把这个大小存下来，下次带着它回来
    public var filled: CGRect?

    public init(window: WindowKey, app: String, label: String, original: CGRect, wasFullScreen: Bool = false,
                wasMinimized: Bool = false, zoom: Int = 0, bundleID: String? = nil, title: String? = nil,
                filled: CGRect? = nil) {
        self.window = window
        self.app = app
        self.label = label
        self.original = original
        self.wasFullScreen = wasFullScreen
        self.wasMinimized = wasMinimized
        self.zoom = zoom
        self.bundleID = bundleID
        self.title = title
        self.filled = filled
    }
}
