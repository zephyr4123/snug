// 设置窗口：顶部是此刻的远程状态，中间一次只显示一页（远程 / 虚拟屏 / 找回屏幕），底部是常用入口。
// 只读 AppState，意图走 AppIntents；窗口自己的界面状态（当前页、设备表草稿）放在 SettingsUIModel
import AppKit
import SwiftUI
import SnugCore

enum SettingsPage: String, CaseIterable, Identifiable {
    case session, virtualDisplay, recovery
    var id: String { rawValue }

    var title: String {
        switch self {
        case .session: "远程"
        case .virtualDisplay: "虚拟屏"
        case .recovery: "找回屏幕"
        }
    }
}

/// 窗口自己的界面状态。SwiftUI 的 @State 在只装命令行工具的环境里编不过（宏插件只随 Xcode 提供），统一放这里
@MainActor
@Observable
final class SettingsUIModel {
    var page: SettingsPage
    let drafts = DeviceDrafts()

    init(page: SettingsPage = .session) { self.page = page }
}

struct SettingsView: View {
    let state: AppState
    let ui: SettingsUIModel
    let intents: any AppIntents
    let navigation: any Navigation
    /// 离屏渲染时设备表不放进滚动视图，便于检查完整排版
    var forRender = false

    var body: some View {
        VStack(spacing: 0) {
            StatusHeader(state: state, intents: intents)
                .padding(20)
            Divider()
            Picker("", selection: Binding(get: { ui.page }, set: { ui.page = $0 })) {
                ForEach(SettingsPage.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 320)
            .padding(.top, 16)
            page
                .padding(20)
            Divider()
            footer
        }
        .frame(width: 720)
    }

    @ViewBuilder private var page: some View {
        switch ui.page {
        case .session: SessionPage(state: state, intents: intents, navigation: navigation)
        case .virtualDisplay: VirtualDisplayPage(state: state, drafts: ui.drafts, intents: intents, forRender: forRender)
        case .recovery: RecoveryPage(state: state, intents: intents)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button("权限设置") { navigation.openPermissions() }
            Button("功能导览") { navigation.openTour() }
            Spacer()
            Button("关于 Snug") { navigation.openAbout() }
            Button("退出 Snug") { intents.quit() }
                .help("先把屏幕还原，再退出")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

/// 顶部：此刻的状态，以及需要用户处理的提示
private struct StatusHeader: View {
    let state: AppState
    let intents: any AppIntents

    var body: some View {
        let text = StatusText(state)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 16) {
                Image(systemName: symbol)
                    .font(.system(size: 24))
                    .foregroundStyle(tint)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(tint.opacity(0.15)))
                VStack(alignment: .leading, spacing: 4) {
                    Text(text.headline).font(.title2.weight(.semibold))
                    ForEach(text.details, id: \.self) { Text($0).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 0)
            }
            if state.legacyAppRunning {
                HStack(spacing: 12) {
                    Callout(symbol: "exclamationmark.triangle.fill",
                            text: "旧版「UU远程伴侣」也在运行，两个会一起改屏幕、互相干扰。", tint: .orange)
                    Spacer(minLength: 0)
                    Button("退出旧版") { intents.quitLegacyApp() }
                }
            }
            if let notice = state.notice {
                Callout(symbol: "exclamationmark.circle.fill", text: notice, tint: .orange)
            }
        }
    }

    private var symbol: String {
        if state.display.wedged { return "exclamationmark.triangle.fill" }
        if state.config.paused { return "pause.fill" }
        switch state.connection {
        case .idle: return "desktopcomputer"
        case .reconnecting: return "arrow.triangle.2.circlepath"
        case .connected: return "iphone.gen3.radiowaves.left.and.right"
        }
    }

    private var tint: Color {
        if state.display.wedged { return .red }
        if state.config.paused { return .secondary }
        return state.connection == .connected ? .green : .accentColor
    }
}

@MainActor
final class SettingsWindowController {
    private let state: AppState
    private let intents: any AppIntents
    private weak var navigation: (any Navigation)?
    private var window: NSWindow?
    private var ui: SettingsUIModel?
    private var closeObserver: (any NSObjectProtocol)?

    init(state: AppState, intents: any AppIntents, navigation: any Navigation) {
        self.state = state
        self.intents = intents
        self.navigation = navigation
    }

    func show(page: SettingsPage?) {
        if let window, let ui {
            if let page { ui.page = page }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        guard let navigation else { return }
        let ui = SettingsUIModel(page: page ?? .session)
        self.ui = ui
        // NSHostingController 做内容控制器：窗口尺寸跟着内容（切页）自动变。
        // 直接给 NSHostingView 设 sizingOptions 会让窗口初始尺寸为 0×0（原作者实测）
        let hosting = NSHostingController(rootView: SettingsView(state: state, ui: ui, intents: intents, navigation: navigation))
        hosting.sizingOptions = [.preferredContentSize]
        let w = NSWindow(contentViewController: hosting)
        w.styleMask = [.titled, .closable, .miniaturizable]
        w.title = "Snug 设置"
        w.isReleasedWhenClosed = false
        w.setContentSize(hosting.view.fittingSize)   // 先定尺寸再居中，否则按 0×0 居中会偏
        w.center()
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w,
                                                               queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.window = nil
                self?.ui = nil
            }
        }
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
