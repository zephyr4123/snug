// 手机屏上的「App 界面」：盖住整块手机屏（连这块屏上的菜单栏一起），看起来像手机上的原生 App。
// 每个状态都讲清楚：
// - 没放窗口：所有窗口，点一下放上来
// - 放着窗口：左上角返回键回到它；下面是它的字号、还原，再下面是其它窗口
// 返回键和提示固定在顶部，不跟着列表滚走；每次回到列表都从最上面看起
// - 正在放：整屏讲明正在打开哪个窗口（换窗口时列表会先变一下，盖住不让它跳）
// - 出了问题：顶部写明出了什么事、怎么办
// 文字只用短词，图标全用 SF Symbols
import AppKit
import SnugCore
import SwiftUI

struct PhoneHomeView: View {
    let state: AppState
    let catalog: WindowCatalog
    let intents: any PhoneIntents

    private var phone: PhoneDesk.State { state.phone }
    private var others: [WindowInfo] { catalog.windows.filter { $0.key != phone.placed?.window.key } }

    private var placing: WindowInfo? {
        if case .placing(let window) = phone.work { window } else { nil }
    }

    var body: some View {
        ZStack {
            list
            if let placing {
                PlacingView(window: placing, icon: catalog.icon(for: placing))
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: placing)
        .background(PhoneStyle.background)
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                header
                if let notice = phone.notice { NoticeBanner(text: notice.text) }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 16)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if let placed = phone.placed {
                            section("当前窗口") {
                                CurrentWindowCard(placed: placed, window: live(placed.window), icon: catalog.icon(for: placed.window),
                                                  work: phone.work, intents: intents)
                            }
                        }
                        section(phone.placed == nil ? "全部窗口" : "其他窗口") { windowList }
                    }
                    .id(Self.top)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.never)
                .onChange(of: phone.listVisible) { _, visible in
                    if visible { proxy.scrollTo(Self.top, anchor: .top) }
                }
            }
        }
        .disabled(phone.work != nil)
    }

    private static let top = "top"

    /// 列表刷新拿到的最新标题（终端的标题跟着命令变），没有就用放上来时的
    private func live(_ window: WindowInfo) -> WindowInfo {
        catalog.windows.first { $0.key == window.key } ?? window
    }

    /// 返回键那一行一直留着：有没有返回键，标题都不跳
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Group {
                if let placed = phone.placed {
                    BackButton(app: placed.window.app) { intents.returnToPlaced() }
                } else {
                    Color.clear
                }
            }
            .frame(height: PhoneStyle.touchTarget, alignment: .leading)
            Text("窗口").font(PhoneStyle.largeTitle)
        }
    }

    @ViewBuilder private var windowList: some View {
        if others.isEmpty {
            EmptyWindows(loading: !catalog.loaded)
        } else {
            LazyVStack(spacing: 12) {
                ForEach(others) { window in
                    Button { intents.pull(window) } label: {
                        WindowRow(window: window, icon: catalog.icon(for: window)).card()
                    }
                    .buttonStyle(PressableStyle())
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

/// 回到手机屏上的窗口：和 iPhone 左上角「‹ App 名」回到上一个 App 一样
private struct BackButton: View {
    let app: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left").font(PhoneStyle.headline)
                Text(app).font(PhoneStyle.body.weight(.medium)).lineLimit(1)
            }
            .foregroundStyle(PhoneStyle.tint)
            .padding(.leading, 16)
            .padding(.trailing, 20)
            .frame(height: PhoneStyle.touchTarget)
            .background(PhoneStyle.tint.opacity(0.12), in: Capsule())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("返回 \(app)")
    }
}

/// 一个窗口：App 图标、App 名、窗口标题
private struct WindowRow: View {
    let window: WindowInfo
    let icon: NSImage

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
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 手机屏上当前的窗口和它的字号、还原。
/// 分两行（操作在下面一行）；这个 App 不能调字号、只剩一个按钮时排成一行
private struct CurrentWindowCard: View {
    let placed: PhoneDesk.Placed
    /// 显示用的窗口（标题是最新的）
    let window: WindowInfo
    let icon: NSImage
    let work: PhoneDesk.Work?
    let intents: any PhoneIntents

    var body: some View {
        Group {
            if placed.zoomable {
                VStack(spacing: 0) {
                    WindowRow(window: window, icon: icon)
                    Divider().padding(.leading, 16)
                    controls
                }
            } else {
                HStack(spacing: 0) {
                    WindowRow(window: window, icon: icon)
                    controls.fixedSize()
                }
            }
        }
        .card()
    }

    private var controls: some View {
        HStack(spacing: 12) {
            if placed.zoomable {
                RoundButton(symbol: "textformat.size.smaller", label: "缩小字号") { intents.zoom(by: -1) }
                    .disabled(placed.zoom <= ZoomBook.range.lowerBound)
                Text(zoomText)
                    .font(PhoneStyle.body.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 72)
                    .contentTransition(.numericText())
                RoundButton(symbol: "textformat.size.larger", label: "放大字号") { intents.zoom(by: 1) }
                    .disabled(placed.zoom >= ZoomBook.range.upperBound)
            }
            Spacer(minLength: 8)
            Button { intents.putBack() } label: {
                HStack(spacing: 8) {
                    if work == .puttingBack {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    Text("还原")
                }
                .font(PhoneStyle.body.weight(.medium))
                .padding(.horizontal, 20)
                .frame(height: PhoneStyle.touchTarget)
                .background(PhoneStyle.background, in: Capsule())
            }
            .buttonStyle(PressableStyle())
        }
        .padding(12)
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

/// 正在把窗口放上来：哪个窗口、在打开。窗口挪好列表就收起，失败了回到列表、顶部写明原因
private struct PlacingView: View {
    let window: WindowInfo
    let icon: NSImage

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: PhoneStyle.iconSize * 2, height: PhoneStyle.iconSize * 2)
            VStack(spacing: 4) {
                Text(window.app).font(PhoneStyle.headline).lineLimit(1)
                if !window.title.isEmpty {
                    Text(window.title).font(PhoneStyle.body).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            VStack(spacing: 8) {
                ProgressView()
                Text("正在打开").font(PhoneStyle.label).foregroundStyle(.secondary)
            }
            .padding(.top, 16)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PhoneStyle.background)
    }
}

private struct NoticeBanner: View {
    let text: StatusText

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text(text.headline).font(PhoneStyle.body.weight(.semibold))
                if let detail = text.detail {
                    Text(detail).font(PhoneStyle.body).foregroundStyle(.secondary)
                }
            }
        }
        .font(PhoneStyle.body)
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
                Text("正在读取窗口").font(PhoneStyle.body).foregroundStyle(.secondary)
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
