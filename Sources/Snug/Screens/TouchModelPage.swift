// 手机、平板屏上的「型号」页：点首页右上角的设备图标进入，改的是这一块屏的型号。最上面是现在用的那台，下面是分辨率（点进去调，
// 见 TouchResolutionPage），再下面自己填分辨率或比例，最后按品牌列出机型库（Assets/device-models.json）里的手机和平板
// （这块屏的类别排前面），顶部能搜型号。选好就回到首页，这块屏当场换成它的比例、分辨率回到默认（换的时候整屏写明「正在调整屏幕」）。
// 和设置里这块屏的详情是同一份配置
import SnugCore
import SwiftUI

struct TouchModelPage: View {
    let screen: ScreenID
    let state: AppState
    @Bindable var pages: TouchPages
    let intents: any TouchIntents
    @Environment(\.topTrailingClear) private var topTrailingClear

    private var query: String { pages.trimmedQuery }
    private var current: DeviceChoice { state.screen(screen)?.device ?? .standard }
    private var orientation: Orientation { state.screen(screen)?.orientation ?? .portrait }

    var body: some View {
        VStack(spacing: 0) {
            // 和 iOS 的导航栏一样：标题居中，右边「完成」。只有「完成」让开右上角，标题仍在整块屏的正中
            ZStack {
                Text("型号").font(TouchTokens.Font.headline.font)
                HStack {
                    Spacer()
                    BarButton(title: "完成", bold: true) { pages.close() }
                }
                .padding(.trailing, topTrailingClear)
            }
            .frame(height: TouchTokens.Size.touchTarget)
            .padding(.horizontal, TouchTokens.Space.margin)
            .padding(.top, TouchTokens.Space.m)
            ScrollView {
                VStack(alignment: .leading, spacing: TouchTokens.Space.xxl) {
                    SearchBar {
                        TextField("搜索型号", text: $pages.query).textFieldStyle(.plain)
                        ClearButton(text: $pages.query)
                    }
                    content
                }
                .padding(.horizontal, TouchTokens.Space.margin)
                .padding(.top, TouchTokens.Space.s)
                .padding(.bottom, TouchTokens.Space.xxl)
            }
            .scrollIndicators(.never)
        }
    }

    @ViewBuilder private var content: some View {
        // 只列这块屏能换成的几类（见 DeviceKind.swappableKinds），这块屏的类别排前面
        let kinds = current.kind.swappableKinds
        let found = state.devices.search(query, in: kinds)
        let brands = found.filter { $0.kind == current.kind } + found.filter { $0.kind != current.kind }
        LazyVStack(alignment: .leading, spacing: TouchTokens.Space.xxl) {
            if query.isEmpty {
                TitledSection("当前 · 这块屏按它调整比例") { CurrentPhone(choice: current, orientation: orientation) }
                if let config = state.screen(screen), let resolution = config.resolution {
                    TitledSection("分辨率") { ResolutionRow(config: config, resolution: resolution) { pages.open(.resolution) } }
                }
            }
            if brands.isEmpty {
                if query.isEmpty {
                    EmptyState(symbol: current.kind.symbol(orientation), title: "未读取到机型库", text: "可在下方自定义比例")
                } else {
                    EmptyState(symbol: "magnifyingglass", title: "无结果", text: "没有与「\(query)」相符的型号")
                }
            }
            // 搜不到时也给自定义：列表里没有的设备就靠它（类别沿用这块屏现在的）
            if query.isEmpty || brands.isEmpty {
                TitledSection("自定义") {
                    CustomScreen(current: current, orientation: orientation) { choose(DeviceChoice(model: nil, screen: $0, kind: current.kind)) }
                }
            }
            ForEach(brands) { brand in
                TitledSection(brand.label(mixed: kinds.count > 1)) {
                    ListCard(brand.models, dividerInset: TouchTokens.Space.margin) { model in
                        ModelRow(model: model, orientation: orientation, selected: model.id == current.model) { choose(DeviceChoice(model)) }
                    }
                }
            }
        }
    }

    private func choose(_ device: DeviceChoice) {
        pages.close()
        intents.setDevice(device)
    }
}

/// 现在用的那台：名字、分辨率
private struct CurrentPhone: View {
    let choice: DeviceChoice
    let orientation: Orientation

    var body: some View {
        HStack(spacing: TouchTokens.Space.l) {
            Image(systemName: choice.kind.symbol(orientation))
                .font(TouchTokens.Font.headline.font.weight(.regular))
                .foregroundStyle(TouchTokens.Color.tint)
                .frame(width: TouchTokens.Size.listIcon)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: TouchTokens.Space.xs) {
                Text(choice.displayName).font(TouchTokens.Font.headline.font).lineLimit(1)
                Text(choice.screen.sizeText(in: orientation)).font(TouchTokens.Font.body.font).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(TouchTokens.Space.l)
        .card()
    }
}

/// 分辨率现在的值和清晰度，点进分辨率页：「默认 / 540 × 950 点 · 画面略软」「660 × 1161 点 / 最清晰」
private struct ResolutionRow: View {
    let config: ScreenConfig
    let resolution: ScreenResolution
    let action: () -> Void

    var body: some View {
        let clarity = resolution.clarity(at: resolution.width(stored: config.baseWidth))
        let detail = ((config.usesDefaultResolution ? [config.sizeText] : []) + [clarity?.short].compactMap { $0 }).joined(separator: " · ")
        Button(action: action) {
            HStack(spacing: TouchTokens.Space.m) {
                VStack(alignment: .leading, spacing: TouchTokens.Space.xs) {
                    Text(config.resolutionText).font(TouchTokens.Font.headline.font).lineLimit(1)
                    if !detail.isEmpty {
                        Text(detail).font(TouchTokens.Font.body.font).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: TouchTokens.Space.s)
                Image(systemName: "chevron.right").font(TouchTokens.Font.body.font.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(TouchTokens.Space.l)
            .frame(minHeight: TouchTokens.Size.touchTarget)
            .contentShape(Rectangle())
            .card()
        }
        .buttonStyle(PressableStyle())
    }
}

/// 自己填分辨率：宽 × 高，横着填也行，比例也行（见 DeviceScreen.custom）。现在用的是自己填的，就先填上它
private struct CustomScreen: View {
    let current: DeviceChoice
    let orientation: Orientation
    let use: (DeviceScreen) -> Void
    @State private var width = ""
    @State private var height = ""

    private var screen: DeviceScreen? { DeviceScreen.custom(Int(width), Int(height)) }

    var body: some View {
        VStack(alignment: .leading, spacing: TouchTokens.Space.m) {
            HStack(spacing: TouchTokens.Space.m) {
                NumberField(placeholder: "宽", text: $width)
                Text("×").font(TouchTokens.Font.body.font).foregroundStyle(.secondary)
                NumberField(placeholder: "高", text: $height)
                PillButton(title: "使用") { screen.map(use) }
                    .disabled(screen == nil)
            }
            Text(orientation.customHint)
                .font(TouchTokens.Font.label.font)
                .foregroundStyle(.secondary)
        }
        .padding(TouchTokens.Space.l)
        .card()
        .onAppear {
            guard let size = current.customScreen?.dimensions(in: orientation) else { return }
            width = String(size.width)
            height = String(size.height)
        }
    }
}

private struct NumberField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(TouchTokens.Font.body.font.monospacedDigit())
            .multilineTextAlignment(.center)
            .padding(.horizontal, TouchTokens.Space.m)
            .fieldBackground()
            .onChange(of: text) { _, new in
                let digits = new.filter(\.isASCII).filter(\.isNumber)
                if digits != new { text = digits }
            }
    }
}

/// 机型库里的一台：型号、分辨率，选中的打勾
private struct ModelRow: View {
    let model: DeviceModel
    let orientation: Orientation
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: TouchTokens.Space.m) {
                VStack(alignment: .leading, spacing: TouchTokens.Space.xs) {
                    Text(model.name).font(TouchTokens.Font.body.font).lineLimit(1)
                    Text(model.screen.sizeText(in: orientation)).font(TouchTokens.Font.label.font).foregroundStyle(.secondary)
                }
                Spacer(minLength: TouchTokens.Space.s)
                if selected {
                    Image(systemName: "checkmark").font(TouchTokens.Font.body.font.weight(.semibold)).foregroundStyle(TouchTokens.Color.tint)
                }
            }
            .padding(.horizontal, TouchTokens.Space.margin)
            .frame(minHeight: TouchTokens.Size.touchTarget + 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
