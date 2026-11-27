// 手机、平板屏上的「分辨率」页：型号页里点「分辨率」进来。和 Mac 上的调整窗口同一套：预览、点数、清晰度、滑块。
// 竖屏上下排；横屏（手机横拿、平板横屏）高度不够，和首页一样左右两栏：左边预览，右边读数和滑块。
// 拖动时屏幕不动，只改这一页的草稿（屏一变，整页连同手指下的滑块都会跟着缩放）；点「应用」才写进配置，
// 回到首页，整屏写「正在调整屏幕」，约 1 秒换好。「取消」回到型号页，什么都不留下
import AppKit
import SnugCore
import SwiftUI

struct TouchResolutionPage: View {
    let screen: ScreenID
    let state: AppState
    let pages: TouchPages
    let intents: any TouchIntents

    var body: some View {
        if let config = state.screen(screen), let resolution = config.resolution {
            Editor(resolution: resolution, stored: config.baseWidth, sidebar: config.device.kind.landscapeSidebar, cancel: { pages.open(.model) }) {
                pages.close()
                intents.setResolution($0)
            }
            // 型号在别处改了（范围跟着变）：草稿按新型号重来
            .id(resolution)
        } else {
            Color.clear.onAppear { pages.close() }
        }
    }
}

private struct Editor: View {
    let resolution: ScreenResolution
    /// 横屏时右栏的宽度（和首页的左栏一样宽）
    let sidebar: CGFloat
    let cancel: () -> Void
    /// 交出要存的值（默认档为 nil）
    let apply: (Int?) -> Void
    @State private var width: Int
    @Environment(\.topTrailingClear) private var topTrailingClear

    init(resolution: ScreenResolution, stored: Int?, sidebar: CGFloat, cancel: @escaping () -> Void, apply: @escaping (Int?) -> Void) {
        self.resolution = resolution
        self.sidebar = sidebar
        self.cancel = cancel
        self.apply = apply
        _width = State(initialValue: resolution.width(stored: stored))
    }

    var body: some View {
        VStack(spacing: 0) {
            // 和型号页的导航栏一样：标题居中，「应用」让开右上角
            ZStack {
                Text("分辨率").font(TouchTokens.Font.headline.font)
                HStack {
                    BarButton(title: "取消", alignment: .leading, action: cancel)
                    Spacer()
                    BarButton(title: "应用", bold: true) { apply(resolution.stored(width)) }
                        .padding(.trailing, topTrailingClear)
                }
            }
            .frame(height: TouchTokens.Size.touchTarget)
            .padding(.horizontal, TouchTokens.Space.margin)
            .padding(.top, TouchTokens.Space.m)
            GeometryReader { geo in
                if geo.size.width > geo.size.height {
                    HStack(spacing: TouchTokens.Space.margin) {
                        ResolutionPreview(resolution: resolution, width: width)
                        VStack(spacing: TouchTokens.Space.xxl) { controls }
                            .frame(width: min(sidebar, geo.size.width * 0.45))
                    }
                    .padding([.horizontal, .bottom], TouchTokens.Space.margin)
                } else {
                    VStack(spacing: 0) {
                        ResolutionPreview(resolution: resolution, width: width)
                            .padding(.horizontal, TouchTokens.Space.margin)
                            .padding(.top, TouchTokens.Space.l)
                        VStack(spacing: TouchTokens.Space.xxl) { controls }
                            .padding(.horizontal, TouchTokens.Space.margin)
                            .padding(.top, TouchTokens.Space.l)
                    }
                }
            }
        }
    }

    /// 读数、滑块、恢复默认：竖屏排在预览下面，横屏排在右栏
    @ViewBuilder private var controls: some View {
        readout
        TouchSlider(resolution: resolution, width: $width)
            .padding(.horizontal, TouchTokens.Space.margin)
            .padding(.vertical, TouchTokens.Space.l)
            .card()
        Button { width = resolution.range.lowerBound } label: {
            Text("恢复默认")
                .font(TouchTokens.Font.body.font)
                .foregroundStyle(TouchTokens.Color.tint)
                .frame(minHeight: TouchTokens.Size.touchTarget)
        }
        .buttonStyle(PressableStyle())
        .opacity(width == resolution.range.lowerBound ? 0 : 1)
        .disabled(width == resolution.range.lowerBound)
    }

    private var readout: some View {
        VStack(spacing: TouchTokens.Space.xs) {
            Text(resolution.sizeText(width) + (width == resolution.range.lowerBound ? "（默认）" : ""))
                .font(TouchTokens.Font.headline.font)
                .monospacedDigit()
            if let clarity = resolution.clarity(at: width) {
                Label(clarity.text, systemImage: clarity.isSharp ? "checkmark.circle.fill" : "circle.lefthalf.filled")
                    .font(TouchTokens.Font.label.font)
                    .foregroundStyle(clarity.isSharp ? Color(nsColor: .systemGreen) : TouchTokens.Color.secondaryLabel)
            }
        }
    }
}

/// 屏上的滑块：手指够得着的粗细，两端大小两个字号图标，下面标「默认」和「最清晰」。
/// 手势翻译开着时，单指滑动到这里是滚动、点一下是点击（见 TouchTranslator），所以：点哪儿跳到哪儿，横着滑一路跟着走，
/// 关了手势翻译时按住拖也行。松手后的惯性滚动不算，手指停在哪就是哪
private struct TouchSlider: View {
    let resolution: ScreenResolution
    @Binding var width: Int

    private typealias Size = TouchTokens.Size.Slider

    var body: some View {
        let range = resolution.range
        let at = { (value: Int) in CGFloat(value - range.lowerBound) / CGFloat(range.upperBound - range.lowerBound) }
        // 刻度排在滑轨正下方、同一栏里，和滑轨一样宽：两头的图标多宽都对得齐
        HStack(alignment: .top, spacing: TouchTokens.Space.m) {
            Image(systemName: "textformat.size.larger").font(.system(size: 28))
                .frame(height: TouchTokens.Size.touchTarget)
            VStack(spacing: TouchTokens.Space.xs) {
                GeometryReader { geo in
                    let span = geo.size.width - Size.thumb
                    ZStack(alignment: .leading) {
                        Capsule().fill(TouchTokens.Color.fill).frame(height: Size.track)
                        Capsule().fill(TouchTokens.Color.tint).frame(width: Size.thumb / 2 + span * at(width), height: Size.track)
                        Circle()
                            .fill(.white)
                            .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                            .frame(width: Size.thumb, height: Size.thumb)
                            .offset(x: span * at(width))
                    }
                    .frame(maxHeight: .infinity)
                    .overlay(SliderInput(value: width, valueAt: { x in
                        resolution.snapped(Double(range.lowerBound) + Double((x - Size.thumb / 2) / span) * Double(range.upperBound - range.lowerBound))
                    }, perPoint: Double(range.upperBound - range.lowerBound) / Double(span), snap: resolution.snapped) { width = $0 })
                }
                .frame(height: TouchTokens.Size.touchTarget)
                GeometryReader { geo in
                    let span = geo.size.width - Size.thumb
                    Text("默认").position(x: Size.thumb / 2, y: 9).fixedSize()
                    if let sharpest = resolution.sharpest {
                        Text("最清晰").position(x: Size.thumb / 2 + span * at(sharpest), y: 9).fixedSize()
                    }
                }
                .frame(height: 18)
                .font(TouchTokens.Font.caption.font)
            }
            Image(systemName: "textformat.size.smaller").font(.system(size: 18))
                .frame(height: TouchTokens.Size.touchTarget)
        }
        .foregroundStyle(TouchTokens.Color.secondaryLabel)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("分辨率")
        .accessibilityValue(resolution.sizeText(width))
        .accessibilityAdjustableAction { direction in
            let step = Double(ScreenFit.step)
            width = resolution.snapped(Double(width) + (direction == .increment ? step : -step))
        }
    }
}

/// 滑块接手指的那一层（AppKit 视图）：按下、拖动给位置，横向滚动按距离挪；惯性滚动不算
private struct SliderInput: NSViewRepresentable {
    let value: Int
    /// 横坐标（视图里的点）→ 一档
    let valueAt: (CGFloat) -> Int
    /// 滑过 1 个点挪多少（点数）
    let perPoint: Double
    let snap: (Double) -> Int
    let onChange: (Int) -> Void

    func makeNSView(context: Context) -> InputView { InputView() }

    func updateNSView(_ view: InputView, context: Context) {
        view.value = value
        view.valueAt = valueAt
        view.perPoint = perPoint
        view.snap = snap
        view.onChange = onChange
    }

    final class InputView: NSView {
        var value = 0
        var valueAt: (CGFloat) -> Int = { _ in 0 }
        var perPoint = 1.0
        var snap: (Double) -> Int = { Int($0) }
        var onChange: (Int) -> Void = { _ in }
        /// 这次滑动没吸档的位置：每次只滑一两个点，按档吸会一直吸回原地
        private var sliding: Double?

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) { follow(event) }
        override func mouseDragged(with event: NSEvent) { follow(event) }

        private func follow(_ event: NSEvent) {
            onChange(valueAt(convert(event.locationInWindow, from: nil).x))
        }

        /// 手势翻译把单指滑动变成滚动：手指往右，滚动量是正的（和小横条的往上滑同一个方向约定）
        override func scrollWheel(with event: NSEvent) {
            guard event.momentumPhase.isEmpty else { return }
            // 新的一次滑动，或者中途被点了一下、改了值：从现在的值接着滑
            if event.phase == .began || sliding.map(snap) != value { sliding = Double(value) }
            guard var at = sliding else { return }
            at += Double(event.scrollingDeltaX) * perPoint
            sliding = at
            onChange(snap(at))
            if event.phase == .ended || event.phase == .cancelled { sliding = nil }
        }
    }
}
