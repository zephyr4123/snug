// 手机、平板屏上界面共用的样式。数值一律直接取设计令牌 TouchTokens（design/design-tokens.json 的 touch），和 Mac 上直接用 MacTokens 一样，
// 不另起别名：手机竖屏 1 点在手机上约 0.82 点，所以字和按钮都按 iOS 的大小放大一档，看起来才和手机上的原生 App 一样大；
// 平板上照样用这些数（V10：约大 1.24 倍，字大、舒服）。颜色用 iOS 的分组背景色（macOS 没有对应的系统色）
import AppKit
import SnugCore
import SwiftUI

extension TouchTokens.Color {
    /// 面板窗口的底色（NSPanel 要 NSColor）
    static var backgroundNSColor: NSColor { NSColor(background) }
}

extension EnvironmentValues {
    /// 这块屏右上角要让开的宽度：顶栏最右边的按钮（首页的「型号」、搜索页的「取消」、型号页的「完成」、裁剪的「完成」）往左挪这么多。
    /// 整块屏共用，建面板时按这块屏的类别注入（见 View.screenPanel），各页只读它、不认类别
    @Entry var topTrailingClear: CGFloat = 0
}

extension DeviceKind {
    /// 屏右上角要让开多少：iPad 上 UU远程 的圆形菜单按钮压着右上角约 45 点（V6）；手机上那里没有 UU 的东西；电脑屏的资源库贴在左边缘（ComputerLibrary），不用这里
    var topTrailingClear: CGFloat {
        switch self {
        case .tablet: TouchTokens.Layout.tabletTopRightClear
        case .phone, .computer: 0
        }
    }

    /// 横屏两栏时窄的那栏（首页左边的 App 列表、分辨率页右边的滑块）多宽：按类别定，窄屏上不超过整宽的 45%
    /// （电脑屏的资源库不分两栏，跟手机走）
    func landscapeSidebar(in width: CGFloat) -> CGFloat {
        let sidebar = switch self {
        case .tablet: TouchTokens.Layout.TabletLandscape.sidebar
        case .phone, .computer: TouchTokens.Layout.PhoneLandscape.sidebar
        }
        return min(sidebar, width * 0.45)
    }
}

extension View {
    /// 盖在这块屏上的面板：注入整块屏共用的环境值
    func screenPanel(_ screen: ScreenID, state: AppState) -> some View {
        ScreenPanelEnvironment(screen: screen, state: state, content: self)
    }
}

/// 单独一层视图读配置：型号从手机换成平板（同一块屏、不重建面板）时，环境值当场跟着变
private struct ScreenPanelEnvironment<Content: View>: View {
    let screen: ScreenID
    let state: AppState
    let content: Content

    var body: some View {
        content.environment(\.topTrailingClear, state.screen(screen)?.device.kind.topTrailingClear ?? 0)
    }
}

/// 按下时轻微变暗，松手恢复（手机上点下去要有反馈）；正在忙、点不了时变淡，看得出来点不了
struct PressableStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(isEnabled ? (configuration.isPressed ? MotionTokens.pressedOpacity : 1) : MotionTokens.disabledOpacity)
            .contentShape(Rectangle())
    }
}
