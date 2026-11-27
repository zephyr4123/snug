// 分辨率的预览：整块屏按选中的点数排版，等比缩进给的地方。Mac 上的调整窗口、屏上的分辨率页共用。
// 画的是一块 Mac 屏的样子（菜单栏加一个终端窗口），只为看出字多大、一屏装多少；清不清晰靠下面那行字说，这里画不出来。
// 最大只放到默认档的 100%：大屏上不再放大，窗口贴着它收紧（见 ResolutionWindowController）。
// 字号、高度直接按缩放后的大小排，不用 scaleEffect：缩放变换会把字先画好再缩，糊
import AppKit
import SnugCore
import SwiftUI

struct ResolutionPreview: View {
    let resolution: ScreenResolution
    /// 选中的那一档（点）
    let width: Int

    var body: some View {
        GeometryReader { geo in
            let box = Self.box(for: resolution, in: geo.size)
            screen(inner: CGSize(width: box.width - 2 * Self.bezel, height: box.height - 2 * Self.bezel))
                .padding(Self.bezel)
                .background(MacTokens.Color.previewBezel, in: RoundedRectangle(cornerRadius: Self.outerRadius, style: .continuous))
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityElement()
        .accessibilityLabel("预览")
        .accessibilityValue(resolution.sizeText(width))
    }

    static let bezel = MacTokens.Size.ResolutionWindow.bezel
    /// 菜单栏、窗口标题栏的高度，外框、屏幕的圆角（Mac 上的点，同原型）
    private static let menuBar: CGFloat = 24
    private static let titleBar: CGFloat = 28
    private static let outerRadius: CGFloat = 12
    private static let innerRadius: CGFloat = 7
    /// 终端的行距：令牌的行高减去等宽字体自己的行高（按字体实际度量，不估）
    private static let codeLineSpacing = MacTokens.Font.code.lineHeight
        - NSLayoutManager().defaultLineHeight(for: .monospacedSystemFont(ofSize: MacTokens.Font.code.size, weight: .regular))

    /// 给的地方里按这块屏的比例摆得下的最大框（含边框），最大到默认档的 100%
    static func box(for resolution: ScreenResolution, in space: CGSize) -> CGSize {
        let full = resolution.size(width: resolution.range.lowerBound)
        let scale = min(1, (space.width - 2 * bezel) / full.width, (space.height - 2 * bezel) / full.height)
        guard scale > 0 else { return .zero }
        return CGSize(width: (full.width * scale).rounded() + 2 * bezel, height: (full.height * scale).rounded() + 2 * bezel)
    }

    /// 屏里的内容：按选中的点数排，再按 inner 的宽缩到框里（s：1 个点画多大）
    private func screen(inner: CGSize) -> some View {
        let s = inner.width / CGFloat(width)
        let code = MacTokens.Font.code
        let bars = (Self.menuBar + Self.titleBar) * s
        let lines = Int(((inner.height - bars) / s / code.lineHeight).rounded(.up))
        return VStack(spacing: 0) {
            HStack(spacing: 16 * s) {
                Text("终端").fontWeight(.semibold)
                ForEach(["Shell", "编辑", "显示", "窗口", "帮助"], id: \.self) { Text($0) }
                Spacer(minLength: 0)
            }
            .font(.system(size: MacTokens.Font.body.size * s))
            .foregroundStyle(.white)
            .padding(.horizontal, 12 * s)
            .frame(height: Self.menuBar * s)
            .background(MacTokens.Color.previewMenuBar)
            Text("~ — zsh")
                .font(.system(size: MacTokens.Font.headline.size * s, weight: .semibold))
                .foregroundStyle(MacTokens.Color.previewTitle)
                .frame(maxWidth: .infinity)
                .frame(height: Self.titleBar * s)
                .background(MacTokens.Color.previewTitleBar)
            // 长行截断、不折行：和终端里一样，屏越宽一行露得越多。高度写死，排不下的行裁掉，不把上面两条挤出去
            Text(Self.sample(lines: lines))
                .font(.system(size: code.size * s, design: .monospaced))
                .lineSpacing(max(0, Self.codeLineSpacing * s))
                .foregroundStyle(MacTokens.Color.previewText)
                .fixedSize()
                .padding(.vertical, 6 * s)
                .padding(.horizontal, 10 * s)
                .frame(width: inner.width, height: max(0, inner.height - bars), alignment: .topLeading)
                .clipped()
        }
        .frame(width: inner.width, height: inner.height)
        .background(MacTokens.Color.previewScreen)
        .clipShape(RoundedRectangle(cornerRadius: Self.innerRadius, style: .continuous))
    }

    /// 一屏终端输出：几段常见的输出轮着排，排够这么多行
    static func sample(lines: Int) -> String {
        (0..<max(0, lines)).map { sampleLines[$0 % sampleLines.count] }.joined(separator: "\n")
    }

    private static let sampleLines = [
        "$ swift build -c release",
        "Building for production...",
        "[12/36] Compiling SnugCore ScreenFit.swift",
        "[27/36] Compiling SnugSystem VirtualDisplayService.swift",
        "Build complete! (24.71s)",
        "$ swift test",
        "Test Suite 'All tests' passed",
        "Executed 412 tests, with 0 failures (0 unexpected) in 3.214 seconds",
        "$ git log --oneline -4",
        "a1b2c3d 修复：窗口放回后保持原来的大小",
        "9f8e7d6 文档：补充多屏的使用说明",
        "5c4b3a2 新增：手机、平板屏的分辨率可以调宽",
        "1a2b3c4 重构：屏幕适配的档位单独成模块",
        "$ tail -f server.log",
        "21:04:15 GET /api/status 200 3ms",
        "21:04:16 POST /api/screens 201 12ms",
        "21:04:18 GET /api/screens/2 200 4ms",
        "",
    ]
}
