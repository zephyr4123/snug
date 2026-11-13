// 手机屏上那个窗口的还原记录：放上去之前写下原位，字号每改一次先记再改，放回原位才删。
// Snug 崩溃时 macOS 会自动撤掉手机屏，窗口被系统挪到别的屏上；下次启动按这份记录放回原处、字号缩回
import CoreGraphics
import Foundation

public struct PhoneRecord: Codable, Equatable, Sendable {
    public var window: WindowKey
    /// 日志里用
    public var label: String
    /// 原位（辅助功能坐标：左上原点）
    public var original: CGRect
    public var wasFullScreen: Bool
    public var wasMinimized: Bool
    /// 比原来放大了几级
    public var zoom: Int

    public init(window: WindowKey, label: String, original: CGRect, wasFullScreen: Bool = false, wasMinimized: Bool = false,
                zoom: Int = 0) {
        self.window = window
        self.label = label
        self.original = original
        self.wasFullScreen = wasFullScreen
        self.wasMinimized = wasMinimized
        self.zoom = zoom
    }
}
