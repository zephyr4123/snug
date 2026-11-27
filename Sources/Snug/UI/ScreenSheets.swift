// 设置窗口「屏幕」页弹出的两张表单，和设置窗口同一种分组样式（标签在左、控件在右，提示写在对应那一行的标签下）：
// - 添加屏幕：先选设备，再选方向（电脑只能横），型号列表只列这一类的；名字不填就按型号和方向起（空着时灰字提示建议的名字）
// - 屏幕详情：一块屏自己的设置。改型号当场换比例、不用重连；方向添加后不能改；删除在左下、红字，再问一次
import AppKit
import SwiftUI
import SnugCore

struct AddScreenSheet: View {
    let state: AppState
    let intents: any AppIntents
    let close: () -> Void

    @State private var kind = DeviceKind.phone
    @State private var orientation = Orientation.portrait
    @State private var device: DeviceChoice?
    /// 用户填的名字。不预填：空着时提示建议的名字，跟着型号和方向变；填了就用填的，换型号不会盖掉
    @State private var name = ""

    /// 手机默认和新装时那块屏一样（机型库里排第一的是折叠屏的内屏，当默认不合适）；平板、电脑是这一类第一台（新的在前）；
    /// 机型库读不出来就用默认的那台换成这一类
    private var chosen: DeviceChoice {
        if let device, device.kind == kind { return device }
        if kind == DeviceChoice.standard.kind { return state.devices.resolve(.standard) }
        if let first = state.devices.brands(in: [kind]).first?.models.first { return DeviceChoice(first) }
        return DeviceChoice(model: nil, screen: DeviceChoice.standard.screen, kind: kind)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MacTokens.Space.l) {
            Text("添加屏幕").font(.headline)
            Form {
                Section {
                    LabeledContent("设备") {
                        Picker("设备", selection: $kind) {
                            ForEach(DeviceKind.allCases, id: \.self) { kind in
                                Label(kind.title, systemImage: kind.symbol(.portrait)).labelStyle(.titleAndIcon).tag(kind)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                    LabeledContent {
                        Picker("方向", selection: $orientation) {
                            Label("竖", systemImage: "rectangle.portrait").labelStyle(.titleAndIcon).tag(Orientation.portrait)
                            Label("横", systemImage: "rectangle").labelStyle(.titleAndIcon).tag(Orientation.landscape)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                        .disabled(kind.allowedOrientations.count < 2)
                    } label: {
                        Text("方向")
                        Text("添加后不能改")
                    }
                    LabeledContent("型号") {
                        DeviceMenu(state: state, kinds: [kind], current: chosen, orientation: orientation) { device = $0 }
                    }
                    LabeledContent {
                        TextField("名字", text: $name, prompt: Text(suggested))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.leading)
                            .frame(width: MacTokens.Size.nameFieldWidth)
                    } label: {
                        Text("名字")
                        Text("显示在远控的屏幕列表里")
                    }
                }
            }
            .sheetForm()
            Tip(symbol: "info.circle", text: "同一时间只推一块屏。新加的屏留给横竖切换，或者换另一台设备时用。")
            if kind == .computer {
                Tip(symbol: "exclamationmark.triangle", text: "没接显示器的 Mac，加任何一块屏都会顶掉系统的默认屏。")
            }
            HStack {
                Spacer()
                Button("取消", action: close).keyboardShortcut(.cancelAction)
                Button("添加") {
                    // 没填就由加屏那一层按型号起名，和这里提示的是同一个（ScreenConfig.suggestedName）
                    intents.addScreen(orientation: orientation, device: chosen, name: name)
                    close()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(MacTokens.Space.xl)
        .frame(width: MacTokens.Size.sheetWidth)
        .onChange(of: kind) {
            orientation = kind.usualOrientation
            device = nil
        }
    }

    private var suggested: String { ScreenConfig.suggestedName(for: chosen, orientation: orientation) }
}

struct ScreenDetailSheet: View {
    let id: ScreenID
    let state: AppState
    let intents: any AppIntents
    let navigation: any Navigation
    let close: () -> Void

    @State private var name = ""
    @State private var confirmingDelete = false

    var body: some View {
        if let screen = state.screen(id) {
            content(screen)
        } else {
            // 删掉了（或配置被别处改了）：没东西可看
            Color.clear.frame(width: 1, height: 1).onAppear(perform: close)
        }
    }

    private func content(_ screen: ScreenConfig) -> some View {
        let other = state.config.otherOrientation(for: screen)
        return VStack(alignment: .leading, spacing: MacTokens.Space.l) {
            HStack(spacing: MacTokens.Space.m) {
                StatusTile(MacTokens.IconTile.screen(symbol: screen.symbol))
                VStack(alignment: .leading, spacing: MacTokens.Space.xxs) {
                    Text(screen.name).font(.headline)
                    Text("\(screen.device.kind.title) · \(screen.sizeText)").foregroundStyle(.secondary)
                }
            }
            Form {
                Section {
                    LabeledContent("名字") {
                        TextField("名字", text: $name)
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.leading)
                            .frame(width: MacTokens.Size.nameFieldWidth)
                            .onSubmit { intents.renameScreen(id, name) }
                    }
                    LabeledContent("型号") {
                        // 触屏和电脑之间不换（见 DeviceKind.swappableKinds）
                        DeviceMenu(state: state, kinds: screen.device.kind.swappableKinds, current: screen.device, orientation: screen.orientation) {
                            intents.setScreenDevice(id, $0)
                        }
                    }
                    LabeledContent("方向") {
                        HStack(spacing: MacTokens.Space.m) {
                            Text("\(screen.orientation.title)屏").foregroundStyle(.secondary)
                            switch other {
                            case .add(let direction):
                                Button("添加\(direction.title)屏", action: useOtherOrientation)
                            case .existing(let saved) where !saved.enabled:
                                Button("启用\(saved.orientation.title)屏", action: useOtherOrientation)
                            default: EmptyView()
                            }
                        }
                    }
                    // 手机、平板才有：电脑屏照搬电脑自己的分辨率
                    if screen.resolution != nil {
                        LabeledContent("分辨率") {
                            HStack(spacing: MacTokens.Space.m) {
                                Text(screen.resolutionText).foregroundStyle(.secondary)
                                Button("调整…") { navigation.openResolution(id) }
                            }
                        }
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: MacTokens.Space.xs) {
                        if case .existing(let saved) = other, saved.enabled {
                            Text("转为\(saved.orientation.title)屏后，在 \(state.remoteNames) 的屏幕列表中选择「\(saved.name)」。")
                        } else if other == .limitReached {
                            Text("已达到 \(ScreenConfig.limit) 块屏幕上限，腾出位置后可添加另一方向。")
                        }
                        Text(screen.resolution == nil ? "改型号当场换比例，不用重连。改名下次远程时生效。"
                                                      : "改型号、分辨率当场生效，不用重连。改名下次远程时生效。")
                    }
                    .font(.callout).foregroundStyle(.secondary)
                }
            }
            .sheetForm()
            HStack {
                Button("删除这块屏…", role: .destructive) { confirmingDelete = true }
                    .buttonStyle(.borderless)
                    .foregroundStyle(MacTokens.Color.danger)
                Spacer()
                Button("完成") {
                    intents.renameScreen(id, name)
                    close()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(MacTokens.Space.xl)
        .frame(width: MacTokens.Size.sheetWidth)
        .onAppear { name = screen.name }
        .confirmationDialog("删除「\(screen.name)」？", isPresented: $confirmingDelete) {
            Button("删除", role: .destructive) {
                close()
                intents.removeScreen(id)
            }
        } message: {
            Text("远程中删除会马上撤掉这块屏，上面的窗口放回原处。")
        }
    }

    private func useOtherOrientation() {
        // 点按时再读配置：连按添加、或在另一处改过型号，都只操作此刻需要的那块屏。
        guard let screen = state.screen(id) else { return }
        switch state.config.otherOrientation(for: screen) {
        case .add(let direction): intents.addScreen(orientation: direction, device: screen.device, name: "")
        case .existing(let saved) where !saved.enabled: intents.setScreenEnabled(saved.id, true)
        default: break
        }
    }
}

/// 表单里的分组：去掉 Form 自带的底色和左右留白，和表单本身的底色、边距对齐
private extension View {
    func sheetForm() -> some View {
        formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, -MacTokens.Space.xl)
            .padding(.vertical, -MacTokens.Space.l)
    }
}

/// 表单底部的一行提示：强调色的图标 + 次要色的字
private struct Tip: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: MacTokens.Space.s) {
            Image(systemName: symbol).foregroundStyle(MacTokens.Color.accent)
            Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .font(.callout)
    }
}

/// 型号：按品牌分组的菜单，选中的打勾；最后一项自己填（弹出小窗）。kinds：只列这几类。
/// 手机、平板自己填的只定比例（叫「自定义比例」，免得和分辨率混），电脑填的是它的分辨率
struct DeviceMenu: View {
    let state: AppState
    let kinds: Set<DeviceKind>
    let current: DeviceChoice
    let orientation: Orientation
    let choose: @MainActor (DeviceChoice) -> Void
    @State private var customizing = false

    var body: some View {
        let brands = state.devices.brands(in: kinds)
        Menu(current.customScreen.map { "\(current.displayName) \($0.sizeText(in: orientation))" } ?? current.displayName) {
            ForEach(brands) { brand in
                Menu(brand.label(mixed: kinds.count > 1)) {
                    ForEach(brand.models) { model in
                        let size = model.screen.sizeText(in: orientation)
                        Toggle(model.name == size ? size : "\(model.name) · \(size)",
                               isOn: Binding(get: { model.id == current.model }, set: { _ in choose(DeviceChoice(model)) }))
                    }
                }
            }
            if !brands.isEmpty { Divider() }
            Toggle(kinds.contains(.computer) ? "自定义分辨率…" : "自定义比例…",
                   isOn: Binding(get: { current.model == nil }, set: { _ in customizing = true }))
        }
        .fixedSize()
        .popover(isPresented: $customizing, arrowEdge: .bottom) {
            CustomScreenForm(current: current, orientation: orientation) { screen in
                customizing = false
                // 自己填的沿用现在的类别
                if let screen { choose(DeviceChoice(model: nil, screen: screen, kind: current.kind)) }
            }
        }
    }
}

extension DeviceCatalog.Brand {
    /// 品牌分节的名字（这里的型号菜单、屏上的型号页共用）：只列一类时就是品牌名；
    /// 几类混着列时手机以外的写明类别（「Apple · 平板」），手机最常见，不写
    func label(mixed: Bool) -> String {
        guard mixed else { return name }
        switch kind {
        case .phone: return name
        case .tablet, .computer: return "\(name) · \(kind.title)"
        }
    }
}

/// 自己填分辨率：宽 × 高，横着填也行，比例也行（见 DeviceScreen.custom）
private struct CustomScreenForm: View {
    let current: DeviceChoice
    let orientation: Orientation
    /// 填好的分辨率；取消为 nil
    let done: (DeviceScreen?) -> Void
    @State private var width: Int?
    @State private var height: Int?

    private var screen: DeviceScreen? { DeviceScreen.custom(width, height) }

    var body: some View {
        VStack(alignment: .leading, spacing: MacTokens.Space.m) {
            Text(current.kind == .computer ? "自定义分辨率" : "自定义比例").font(.headline)
            HStack(spacing: MacTokens.Space.s) {
                TextField("宽", value: $width, format: .number.grouping(.never))
                Text("×").foregroundStyle(.secondary)
                TextField("高", value: $height, format: .number.grouping(.never))
            }
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.center)
            Text(current.kind == .computer ? "电脑上「显示器」设置里的分辨率，如 1920 × 1080" : orientation.customHint)
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("取消") { done(nil) }
                    .keyboardShortcut(.cancelAction)
                Button("使用") { done(screen) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(screen == nil)
            }
        }
        .padding(MacTokens.Space.l)
        .frame(width: MacTokens.Size.resolutionPopoverWidth)
        .onAppear {
            guard let size = current.customScreen?.dimensions(in: orientation) else { return }
            width = size.width
            height = size.height
        }
    }
}
