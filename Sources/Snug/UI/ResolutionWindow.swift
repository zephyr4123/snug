// Mac 上调分辨率的窗口（屏幕详情里点「调整…」打开）：预览占满窗口，底栏左边点数和清晰度、中间滑块、右边按钮。
// 拖动只改这里的草稿，点「应用」才写进配置，之后照改配置的老路在线换档位；取消、Esc、关窗口都不留下什么。
// 一次只开一个：再点「调整…」（哪怕是另一块屏）先关掉旧的。窗口按打开时所在那块屏的可用区域定大小，
// 预览最大到默认档的 100%（大屏上不放大，窗口贴着它收紧），可以拖大拖小
import AppKit
import SnugCore
import SwiftUI

@MainActor
final class ResolutionWindowController {
    private let state: AppState
    private let intents: any AppIntents
    private var window: NSWindow?

    init(state: AppState, intents: any AppIntents) {
        self.state = state
        self.intents = intents
    }

    /// screen：在哪块屏上打开（设置窗口所在的那块）
    func show(_ id: ScreenID, on screen: NSScreen?) {
        window?.close()
        guard let config = state.screen(id), let resolution = config.resolution else { return }
        let view = ResolutionWindowView(id: id, state: state, intents: intents) { [weak self] in self?.window?.close() }
        let hosting = NSHostingController(rootView: view)
        // 窗口大小由这里和用户定，不跟着内容的理想尺寸走
        hosting.sizingOptions = []
        let w = NSWindow(contentViewController: hosting)
        w.styleMask = [.titled, .closable, .resizable]
        w.title = "调整分辨率 · \(config.name)"
        w.isReleasedWhenClosed = false
        w.contentMinSize = NSSize(width: Size.minWidth, height: Size.minHeight)
        w.setContentSize(Self.contentSize(for: resolution, on: screen))
        if let screen { w.center(on: screen) } else { w.center() }
        window = w
        w.present(activating: true)
    }

    private typealias Size = MacTokens.Size.ResolutionWindow

    /// 预览按默认档的 100% 摆，放不下就等比缩到这块屏可用区域的 screenShare 里；再加上四周留白和底栏
    static func contentSize(for resolution: ScreenResolution, on screen: NSScreen?) -> NSSize {
        let area = screen?.visibleFrame.size ?? NSSize(width: 1280, height: 800)
        let chrome = NSSize(width: 2 * MacTokens.Space.xl, height: 2 * MacTokens.Space.xl + Size.barHeight)
        let room = CGSize(width: area.width * Size.screenShare - chrome.width, height: area.height * Size.screenShare - chrome.height)
        let box = ResolutionPreview.box(for: resolution, in: room)
        return NSSize(width: max(Size.minWidth, box.width + chrome.width), height: max(Size.minHeight, box.height + chrome.height))
    }
}

/// 读这块屏此刻的配置：屏删了就关窗口；型号在别处改了（范围跟着变），草稿按新型号重来
struct ResolutionWindowView: View {
    let id: ScreenID
    let state: AppState
    let intents: any AppIntents
    let close: () -> Void

    var body: some View {
        if let config = state.screen(id), let resolution = config.resolution {
            ResolutionEditor(resolution: resolution, stored: config.baseWidth, cancel: close) {
                intents.setScreenResolution(id, $0)
                close()
            }
            .id(resolution)
        } else {
            Color.clear.onAppear(perform: close)
        }
    }
}

private struct ResolutionEditor: View {
    let resolution: ScreenResolution
    let cancel: () -> Void
    /// 交出要存的值（默认档为 nil）
    let apply: (Int?) -> Void
    @State private var width: Int

    init(resolution: ScreenResolution, stored: Int?, cancel: @escaping () -> Void, apply: @escaping (Int?) -> Void) {
        self.resolution = resolution
        self.cancel = cancel
        self.apply = apply
        _width = State(initialValue: resolution.width(stored: stored))
    }

    private typealias Size = MacTokens.Size.ResolutionWindow

    var body: some View {
        VStack(spacing: 0) {
            ResolutionPreview(resolution: resolution, width: width)
                .padding(MacTokens.Space.xl)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(MacTokens.Color.fill)
            // 读数、按钮按自己的宽度摆，滑块占中间剩下的（最宽 sliderWidth）。分隔线压在底栏上、不占高度，窗口大小照 contentSize 算
            HStack(spacing: MacTokens.Space.xl) {
                readout.fixedSize()
                Spacer(minLength: 0)
                ResolutionSlider(resolution: resolution, width: $width).frame(maxWidth: Size.sliderWidth)
                Spacer(minLength: 0)
                buttons.fixedSize()
            }
            .padding(.horizontal, MacTokens.Space.xl)
            .frame(height: Size.barHeight)
            .overlay(alignment: .top) { Divider() }
        }
    }

    private var readout: some View {
        VStack(alignment: .leading, spacing: MacTokens.Space.xxs) {
            Text(resolution.readout(width))
                .font(MacTokens.Font.headline.font)
                .monospacedDigit()
            if let clarity = resolution.clarity(at: width) {
                Label(clarity.text, systemImage: clarity.symbol)
                    .font(MacTokens.Font.callout.font)
                    .foregroundStyle(clarity.isSharp ? MacTokens.Color.positive : MacTokens.Color.secondaryLabel)
            }
        }
    }

    private var buttons: some View {
        HStack(spacing: MacTokens.Space.s) {
            Button("恢复默认") { width = resolution.range.lowerBound }
                .buttonStyle(.borderless)
                .foregroundStyle(MacTokens.Color.accent)
                .opacity(width == resolution.range.lowerBound ? 0 : 1)
                .disabled(width == resolution.range.lowerBound)
            Button("取消", action: cancel).keyboardShortcut(.cancelAction)
            Button("应用") { apply(resolution.stored(width)) }.keyboardShortcut(.defaultAction)
        }
    }
}

/// Mac 上的滑块：系统滑块，两端大小两个字号图标，下面标「默认」和「最清晰」；值吸到 ScreenResolution 的档
private struct ResolutionSlider: View {
    let resolution: ScreenResolution
    @Binding var width: Int
    /// 系统滑块两头留给把手的宽度：刻度按把手中心对齐
    private static let knobInset: CGFloat = 10

    var body: some View {
        let range = resolution.range
        HStack(alignment: .top, spacing: MacTokens.Space.s) {
            Image(systemName: "textformat.size.larger").font(.system(size: 17))
            VStack(spacing: MacTokens.Space.xxs) {
                Slider(value: Binding(get: { Double(width) }, set: { width = resolution.snapped($0) }),
                       in: Double(range.lowerBound)...Double(range.upperBound))
                    .labelsHidden()
                    .accessibilityLabel("分辨率")
                    .accessibilityValue(resolution.sizeText(width))
                GeometryReader { geo in
                    let span = geo.size.width - 2 * Self.knobInset
                    Text("默认").position(x: Self.knobInset, y: 7).fixedSize()
                    if let sharpest = resolution.sharpest {
                        let at = Double(sharpest - range.lowerBound) / Double(range.upperBound - range.lowerBound)
                        Text("最清晰").position(x: Self.knobInset + span * at, y: 7).fixedSize()
                    }
                }
                .frame(height: 14)
                .font(MacTokens.Font.callout.font)
                .foregroundStyle(MacTokens.Color.secondaryLabel)
            }
            Image(systemName: "textformat.size.smaller").font(.system(size: 12)).padding(.top, 3)
        }
        .foregroundStyle(MacTokens.Color.secondaryLabel)
    }
}
