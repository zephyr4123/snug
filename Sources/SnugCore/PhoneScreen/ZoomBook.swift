// 字号：手机屏已经是 2 倍高清能做到的最小尺寸（短边 540 点），字再大只能靠 App 自己的 ⌘+ / ⌘-。
// 放上手机屏时按这个 App 记住的级数放大（没记过就用设置里的默认级数），放回原位时按同样的级数缩回，
// 不用 ⌘0：那会把用户原来的字号也一起清掉。
// 浏览器不在名单里：它们按网站记缩放、一直记着，放大会连带同一网站的其它窗口，
// 换了网页再缩回又缩到别的网站上，改动收不回来。网页在 540 点宽的屏上本来就按窄屏排版
import Foundation

public struct ZoomBook: Codable, Equatable, Sendable {
    /// 支持 ⌘+ / ⌘- 调字号的 App。不在名单里的不发按键：⌘= 在别的 App 里可能是别的意思
    public static let zoomableApps: Set<String> = [
        "com.mitchellh.ghostty", "com.apple.Terminal", "com.googlecode.iterm2",
        "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "dev.zed.Zed",
    ]
    /// 相对原来最多缩小 / 放大几级
    public static let range = -4...8

    /// bundle ID → 这个 App 在手机屏上放大几级
    public private(set) var remembered: [String: Int] = [:]

    public init() {}

    public static func isZoomable(_ bundleID: String?) -> Bool {
        bundleID.map(zoomableApps.contains) ?? false
    }

    /// 放上手机屏时该放大几级；不支持调字号的 App 返回 0
    public func steps(for bundleID: String?, default fallback: Int) -> Int {
        guard let bundleID, Self.isZoomable(bundleID) else { return 0 }
        return (remembered[bundleID] ?? fallback).clamped(to: Self.range)
    }

    public mutating func remember(_ steps: Int, for bundleID: String) {
        remembered[bundleID] = steps.clamped(to: Self.range)
    }
}
