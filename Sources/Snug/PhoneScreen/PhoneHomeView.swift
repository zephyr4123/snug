// 手机屏空着时显示的「App 界面」：盖住整块手机屏（连这块屏上的菜单栏一起），看起来像手机上的原生 App。
// 上面是手机屏上当前的窗口和它的操作（字号、还原），下面是 Mac 上其它窗口，点一下就放上来。
// 右上角切换横屏 / 竖屏。横屏两列，竖屏一列。文字只用短词，图标全用 SF Symbols
import AppKit
import SnugCore
import SwiftUI

struct PhoneHomeView: View {
    let state: AppState
    let catalog: WindowCatalog
    let intents: any PhoneIntents

    private var phone: PhoneDesk.State { state.phone }
    private var others: [WindowInfo] { catalog.windows.filter { $0.key != phone.placed?.window.key } }
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: phone.orientation == .landscape ? 2 : 1)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if let notice = phone.notice { NoticeBanner(text: notice) }
                if let placed = phone.placed {
                    section("当前窗口") {
                        CurrentWindowCard(placed: placed, catalog: catalog, busy: phone.work != nil,
                                          compact: phone.orientation == .landscape || !placed.zoomable, intents: intents)
                    }
                }
                section(phone.placed == nil ? "全部窗口" : "其他窗口") { windowGrid }
            }
            .padding(.horizontal, 20)
            .padding(.top, 32)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.never)
        .background(PhoneStyle.background)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            Text("窗口").font(PhoneStyle.largeTitle)
            Spacer(minLength: 8)
            RotateButton(orientation: phone.orientation, busy: phone.work != nil) { intents.rotate() }
        }
    }

    @ViewBuilder private var windowGrid: some View {
        if others.isEmpty {
            EmptyWindows(loading: !catalog.loaded)
        } else {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(others) { window in
                    Button { intents.pull(window) } label: {
                        WindowRow(window: window, icon: catalog.icon(for: window), placing: phone.work == .placing(window.key))
                            .card()
                    }
                    .buttonStyle(PressableStyle())
                    .disabled(phone.work != nil)
                }
            }
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(PhoneStyle.label)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            content()
        }
    }
}

/// 一个窗口：App 图标、App 名、窗口标题
private struct WindowRow: View {
    let window: WindowInfo
    let icon: NSImage
    var placing = false
    var trailing: String?

    var body: some View {
        HStack(spacing: 16) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: PhoneStyle.iconSize, height: PhoneStyle.iconSize)
            VStack(alignment: .leading, spacing: 4) {
                Text(window.app).font(PhoneStyle.headline).lineLimit(1)
                Text(window.title.isEmpty ? "无标题" : window.title)
                    .font(PhoneStyle.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if placing {
                ProgressView().controlSize(.small)
            } else if let trailing {
                Image(systemName: trailing).font(PhoneStyle.body).foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 手机屏上当前的窗口：点它回到这个窗口；旁边是字号和还原。
/// 竖屏分两行（操作在下面一行）；横屏高度紧张、或者这个 App 不能调字号只剩一个按钮时，排成一行
private struct CurrentWindowCard: View {
    let placed: PhoneDesk.Placed
    let catalog: WindowCatalog
    let busy: Bool
    let compact: Bool
    let intents: any PhoneIntents

    var body: some View {
        Group {
            if compact {
                HStack(spacing: 0) {
                    window
                    controls.fixedSize()
                }
            } else {
                VStack(spacing: 0) {
                    window
                    Divider().padding(.leading, 16)
                    controls
                }
            }
        }
        .card()
    }

    private var window: some View {
        Button { intents.returnToPlaced() } label: {
            WindowRow(window: placed.window, icon: catalog.icon(for: placed.window), trailing: "chevron.right")
        }
        .buttonStyle(PressableStyle())
    }

    private var controls: some View {
        HStack(spacing: 12) {
            if placed.zoomable {
                RoundButton(symbol: "textformat.size.smaller", label: "缩小字号") { intents.zoom(by: -1) }
                Text(zoomText)
                    .font(PhoneStyle.body.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 72)
                    .contentTransition(.numericText())
                RoundButton(symbol: "textformat.size.larger", label: "放大字号") { intents.zoom(by: 1) }
            }
            Spacer(minLength: 8)
            Button { intents.putBack() } label: {
                Label("还原", systemImage: "arrow.uturn.backward")
                    .font(PhoneStyle.body.weight(.medium))
                    .padding(.horizontal, 20)
                    .frame(height: PhoneStyle.touchTarget)
                    .background(PhoneStyle.background, in: Capsule())
            }
            .buttonStyle(PressableStyle())
        }
        .padding(12)
        .disabled(busy)
    }

    private var zoomText: String {
        placed.zoom == 0 ? "默认字号" : "字号 \(placed.zoom > 0 ? "+" : "")\(placed.zoom)"
    }
}

private struct RoundButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(PhoneStyle.headline)
                .frame(width: PhoneStyle.touchTarget, height: PhoneStyle.touchTarget)
                .background(PhoneStyle.background, in: Circle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }
}

private struct RotateButton: View {
    let orientation: Orientation
    let busy: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if busy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: orientation == .portrait ? "rectangle.landscape.rotate" : "rectangle.portrait.rotate")
                }
                Text(orientation == .portrait ? "横屏" : "竖屏")
            }
            .font(PhoneStyle.body.weight(.medium))
            .padding(.horizontal, 20)
            .frame(height: PhoneStyle.touchTarget)
            .background(PhoneStyle.card, in: Capsule())
        }
        .buttonStyle(PressableStyle())
        .disabled(busy)
    }
}

private struct NoticeBanner: View {
    let text: String

    var body: some View {
        Label {
            Text(text).font(PhoneStyle.body)
        } icon: {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

private struct EmptyWindows: View {
    let loading: Bool

    var body: some View {
        VStack(spacing: 12) {
            if loading {
                ProgressView()
            } else {
                Image(systemName: "macwindow").font(PhoneStyle.largeTitle).foregroundStyle(.tertiary)
                Text("暂无窗口").font(PhoneStyle.body).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}

private extension View {
    func card() -> some View {
        background(PhoneStyle.card, in: RoundedRectangle(cornerRadius: PhoneStyle.cornerRadius, style: .continuous))
    }
}
