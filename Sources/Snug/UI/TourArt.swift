// 导览配图（800×500 pt，顶部亮、底部渐暗，衔接 TourKit 的深色文字区）。
// 由 `Snug --render-tour <目录>` 渲染成 1600×1000 PNG 放进 Assets/Tour，打包时拷进 Contents/Resources
import SwiftUI

@MainActor
enum TourArt {
    static let all: [String: AnyView] = [
        "tour-welcome": AnyView(WelcomeArt()),
        "tour-match": AnyView(MatchArt()),
        "tour-physical": AnyView(PhysicalArt()),
        "tour-safety": AnyView(SafetyArt()),
        "tour-setup": AnyView(SetupArt()),
    ]
}

private let accent = LinearGradient(colors: [Color(red: 0.36, green: 0.62, blue: 1.0), Color(red: 0.55, green: 0.40, blue: 1.0)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing)

private struct ArtBackground<Content: View>: View {
    let tint: Color
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.10, green: 0.12, blue: 0.22), Color(red: 0.04, green: 0.04, blue: 0.08)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [tint.opacity(0.45), .clear], center: .init(x: 0.5, y: 0.35), startRadius: 10, endRadius: 420)
            content.offset(y: -20)
        }
        .frame(width: 800, height: 500)
        .clipped()
    }
}

/// 带边框的设备屏幕
private struct Screen<Content: View>: View {
    let width: CGFloat
    let height: CGFloat
    var radius: CGFloat = 14
    var bezel: CGFloat = 8
    var lit = true
    @ViewBuilder let content: Content

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Color(white: 0.16))
            .overlay(
                RoundedRectangle(cornerRadius: radius - bezel / 2, style: .continuous)
                    .fill(lit ? AnyShapeStyle(accent.opacity(0.9)) : AnyShapeStyle(Color(white: 0.07)))
                    .overlay(content)
                    .padding(bezel)
            )
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(Color.white.opacity(0.18), lineWidth: 1))
            .frame(width: width, height: height)
            .shadow(color: lit ? Color.blue.opacity(0.45) : .clear, radius: 24)
    }
}

private struct Monitor: View {
    var lit = true
    var body: some View {
        VStack(spacing: 0) {
            Screen(width: 300, height: 180, lit: lit) {
                if !lit {
                    Image(systemName: "power").font(.system(size: 34, weight: .semibold)).foregroundStyle(Color(white: 0.35))
                }
            }
            Rectangle().fill(Color(white: 0.22)).frame(width: 34, height: 34)
            Capsule().fill(Color(white: 0.24)).frame(width: 120, height: 8)
        }
    }
}

private struct Laptop: View {
    var lit = true
    var body: some View {
        VStack(spacing: 0) {
            Screen(width: 200, height: 128, radius: 10, bezel: 6, lit: lit) {
                if !lit {
                    Image(systemName: "power").font(.system(size: 26, weight: .semibold)).foregroundStyle(Color(white: 0.35))
                }
            }
            UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8)
                .fill(Color(white: 0.24)).frame(width: 236, height: 10)
        }
    }
}

private struct Chip: View {
    let text: String
    var symbol: String?
    var body: some View {
        HStack(spacing: 6) {
            if let symbol { Image(systemName: symbol) }
            Text(text)
        }
        .font(.system(size: 15, weight: .semibold, design: .rounded))
        .foregroundStyle(.white)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Capsule().fill(Color.white.opacity(0.14)))
        .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1))
    }
}

private struct WelcomeArt: View {
    var body: some View {
        ArtBackground(tint: .blue) {
            HStack(alignment: .bottom, spacing: 46) {
                Screen(width: 190, height: 132, radius: 16, bezel: 9) {
                    Image(systemName: "hand.point.up.left.fill").font(.system(size: 40)).foregroundStyle(.white.opacity(0.9))
                }
                .padding(.bottom, 30)
                Image(systemName: "dot.radiowaves.right")
                    .font(.system(size: 44, weight: .semibold)).foregroundStyle(accent)
                    .padding(.bottom, 92)
                Monitor()
            }
        }
    }
}

private struct MatchArt: View {
    var body: some View {
        ArtBackground(tint: .purple) {
            HStack(spacing: 40) {
                VStack(spacing: 16) {
                    Screen(width: 216, height: 100, radius: 20, bezel: 8) {}
                    Chip(text: "iPhone 横屏")
                }
                Image(systemName: "arrow.right").font(.system(size: 36, weight: .bold)).foregroundStyle(.white.opacity(0.8))
                VStack(spacing: 16) {
                    Screen(width: 320, height: 148) {
                        VStack(spacing: 4) {
                            Text("2868 × 1320").font(.system(size: 30, weight: .bold, design: .rounded))
                            Text("高清（HiDPI）").font(.system(size: 15, weight: .semibold, design: .rounded)).opacity(0.85)
                        }
                        .foregroundStyle(.white)
                    }
                    Chip(text: "铺满 · 无黑边", symbol: "checkmark.circle.fill")
                }
            }
        }
    }
}

private struct PhysicalArt: View {
    var body: some View {
        ArtBackground(tint: .indigo) {
            VStack(spacing: 26) {
                VStack(spacing: 12) {
                    Screen(width: 230, height: 160, radius: 16, bezel: 9) {
                        Image(systemName: "ipad.landscape").font(.system(size: 54)).foregroundStyle(.white)
                    }
                    Chip(text: "只留虚拟屏幕", symbol: "sparkles")
                }
                HStack(alignment: .bottom, spacing: 40) {
                    Laptop(lit: false)
                    Monitor(lit: false)
                }
                .scaleEffect(0.62)
                .frame(height: 150)
                .opacity(0.8)
            }
            .offset(y: 10)
        }
    }
}

private struct KeyCap: View {
    let label: String
    /// 修饰键的英文名（照顾不熟悉符号的新用户）
    var name: String? = nil
    var body: some View {
        VStack(spacing: 4) {
            Text(label).font(.system(size: name == nil ? 40 : 34, weight: .medium, design: .rounded))
            if let name { Text(name).font(.system(size: 14, weight: .medium)) }
        }
            .foregroundStyle(.white)
            .frame(width: name == nil ? 84 : 104, height: 84)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(white: 0.20)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.25), lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 6, y: 5)
    }
}

private struct SafetyArt: View {
    var body: some View {
        ArtBackground(tint: .teal) {
            VStack(spacing: 30) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 92))
                    .foregroundStyle(accent)
                    .shadow(color: .blue.opacity(0.6), radius: 20)
                HStack(spacing: 14) {
                    KeyCap(label: "⌃", name: "control")
                    KeyCap(label: "⌥", name: "option")
                    KeyCap(label: "⌘", name: "command")
                    KeyCap(label: "9")
                }
            }
        }
    }
}

private struct SetupArt: View {
    private struct Row: View {
        let symbol: String
        let title: String
        var body: some View {
            HStack(spacing: 16) {
                Image(systemName: symbol).font(.system(size: 28)).foregroundStyle(accent).frame(width: 40)
                Text(title).font(.system(size: 24, weight: .semibold)).foregroundStyle(.white)
                Spacer()
                Image(systemName: "circle").font(.system(size: 26)).foregroundStyle(.white.opacity(0.5))
            }
            .padding(.horizontal, 24)
            .frame(width: 420, height: 78)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.10)))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.2), lineWidth: 1))
        }
    }

    var body: some View {
        ArtBackground(tint: .blue) {
            VStack(spacing: 18) {
                Row(symbol: "hand.raised.fill", title: "允许读取设备名称")
                Row(symbol: "rectangle.on.rectangle", title: "需要时打开虚拟屏")
            }
        }
    }
}
