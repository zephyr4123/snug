// 设置界面共用的小件：分组卡片、开关行、快捷键示意、设备图标
import SwiftUI
import SnugCore

/// 一组设置：系统控件底色、10pt 圆角
struct Card<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content() }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(nsColor: .separatorColor).opacity(0.6)))
    }
}

/// 标题 + 一句说明 + 右侧开关
struct SettingToggle: View {
    let title: String
    var tag: String?
    let detail: String
    let isOn: Bool
    var enabled = true
    let set: @MainActor @Sendable (Bool) -> Void

    var body: some View {
        Toggle(isOn: Binding(get: { isOn }, set: set)) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title).font(.headline)
                    if let tag { Text(tag).font(.caption).foregroundStyle(.secondary) }
                }
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
        .disabled(!enabled)
    }
}

/// 一行带图标的提示
struct Callout: View {
    let symbol: String
    let text: String
    var tint: Color = .secondary

    var body: some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).foregroundStyle(tint)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }
}

/// 快捷键示意图：⌃ ⌥ ⌘ 9 四个键
struct HotkeyKeysView: View {
    var body: some View {
        HStack(spacing: 8) {
            cap("⌃", "control")
            plus
            cap("⌥", "option")
            plus
            cap("⌘", "command")
            plus
            cap("9", nil)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("快捷键：同时按下 control、option、command 和 9")
    }

    private var plus: some View {
        Image(systemName: "plus").font(.callout.weight(.bold)).foregroundStyle(.secondary)
    }

    private func cap(_ symbol: String, _ name: String?) -> some View {
        VStack(spacing: 2) {
            Text(symbol).font(.system(size: 20, weight: .semibold))
            if let name { Text(name).font(.caption) }
        }
        .foregroundStyle(.white)
        .frame(width: name == nil ? 48 : 64, height: 48)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor))
    }
}

/// 简笔安卓机器人（SF Symbols 没有安卓图标）
private struct AndroidGlyph: View {
    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height) / 18
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
            var head = Path()
            head.addArc(center: p(9, 8), radius: 6 * s, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
            head.closeSubpath()
            ctx.fill(head, with: .color(.white))
            var antenna = Path()
            antenna.move(to: p(5.6, 3.6)); antenna.addLine(to: p(4.2, 1.4))
            antenna.move(to: p(12.4, 3.6)); antenna.addLine(to: p(13.8, 1.4))
            ctx.stroke(antenna, with: .color(.white), style: StrokeStyle(lineWidth: 1.1 * s, lineCap: .round))
            for x in [6.6, 11.4] as [CGFloat] {
                ctx.fill(Path(ellipseIn: CGRect(origin: p(x - 0.8, 4.9), size: CGSize(width: 1.6 * s, height: 1.6 * s))),
                         with: .color(.accentColor))
            }
            ctx.fill(Path(roundedRect: CGRect(origin: p(3, 9), size: CGSize(width: 12 * s, height: 7.5 * s)), cornerRadius: 1.8 * s),
                     with: .color(.white))
        }
    }
}

/// 仿 UU「全部设备」的设备图标：按系统类型画
struct DeviceIcon: View {
    let device: DeviceProfile

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.accentColor)
            .frame(width: 32, height: 32)
            .overlay(glyph.foregroundStyle(.white))
    }

    @ViewBuilder private var glyph: some View {
        switch device.platform ?? "" {
        case "macos", "ios": Image(systemName: "apple.logo").font(.system(size: 16, weight: .medium))
        case "android": AndroidGlyph().frame(width: 20, height: 20)
        case "windows": Image(systemName: "square.grid.2x2.fill").font(.system(size: 14))
        default: Image(systemName: device.inComputerGroup ? "desktopcomputer" : "ipad.and.iphone").font(.system(size: 14))
        }
    }
}
