// 手机屏上界面的尺寸与颜色。手机屏 1 点在手机上约 0.82 点，所以字和按钮都按 iOS 的大小放大一档，
// 看起来才和手机上的原生 App 一样大；颜色用 iOS 的分组背景色（macOS 没有对应的系统色）
import AppKit
import SwiftUI

enum PhoneStyle {
    // 字号：四档
    static let largeTitle = Font.system(size: 40, weight: .bold)
    static let headline = Font.system(size: 22, weight: .semibold)
    static let body = Font.system(size: 18)
    static let label = Font.system(size: 15, weight: .medium)

    /// 手指点得准的最小高度（iOS 44 点 × 1.25）
    static let touchTarget: CGFloat = 56
    static let cornerRadius: CGFloat = 12
    static let iconSize: CGFloat = 48

    /// iOS systemGroupedBackground：浅色 #F2F2F7，深色纯黑
    static let background = Color(nsColor: dynamic(light: NSColor(srgbRed: 0.949, green: 0.949, blue: 0.969, alpha: 1),
                                                   dark: .black))
    /// iOS secondarySystemGroupedBackground：浅色白，深色 #1C1C1E
    static let card = Color(nsColor: dynamic(light: .white,
                                             dark: NSColor(srgbRed: 0.110, green: 0.110, blue: 0.118, alpha: 1)))
    static var backgroundNSColor: NSColor { NSColor(background) }
    /// iOS 的默认强调色（systemBlue）；不跟 Mac 的强调色走，手机上的 App 都是这个蓝
    static let tint = Color(nsColor: .systemBlue)

    private static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }
}

/// 按下时轻微变暗，松手恢复（手机上点下去要有反馈）；正在忙、点不了时变淡，看得出来点不了
struct PressableStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.4)
            .contentShape(Rectangle())
    }
}
