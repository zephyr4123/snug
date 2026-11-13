// 用户设置（config.json）。App 层的 AppController 是唯一写入者
import Foundation

public struct AppConfig: Codable, Equatable, Sendable {
    /// 总开关：用手机远程时加一块手机屏
    public var phoneScreen = true
    /// 手机屏上把 UU 发来的单指操作翻译成 iPhone 的手势
    public var gestures = true
    /// 窗口放上手机屏时，字号默认放大几级（每个 App 改过之后按它自己记住的级数）
    public var zoomSteps = 2
    /// 是否已看过首次启动的欢迎页
    public var welcomed = false

    public static let zoomStepsRange = 0...4

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case phoneScreen, gestures, zoomSteps, welcomed
    }

    // 每一项都有默认值：以后加字段、或者手改漏了某项，都不会让整份配置被判为损坏
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppConfig()
        phoneScreen = try c.decodeIfPresent(Bool.self, forKey: .phoneScreen) ?? d.phoneScreen
        gestures = try c.decodeIfPresent(Bool.self, forKey: .gestures) ?? d.gestures
        zoomSteps = try c.decodeIfPresent(Int.self, forKey: .zoomSteps).map { $0.clamped(to: Self.zoomStepsRange) } ?? d.zoomSteps
        welcomed = try c.decodeIfPresent(Bool.self, forKey: .welcomed) ?? d.welcomed
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}
