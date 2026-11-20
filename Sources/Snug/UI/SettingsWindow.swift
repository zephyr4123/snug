// 设置窗口：macOS 设置窗口的样式，顶部工具栏分三页（界面以 design/prototype 为准）：
// - 屏幕：此刻的远程状态，要处理的问题各一行；屏幕列表（开关、在看、ⓘ 进详情）、添加屏幕、设为主屏
// - 触控：手势、字号放大、截图，写明只作用于手机和平板屏
// - 通用：开机启动、权限、软件更新和更新源、退出 Snug
// 只管某一块屏的（型号、名字、删除）放进那块屏的详情（见 ScreenSheets）。只读 AppState，意图走 AppIntents。
// 说明文字：结论最多一行留在页面上，理由收进行末「为什么？」的气泡
import AppKit
import PermissionFlow
import SwiftUI
import SnugCore

// MARK: 屏幕

struct ScreensPage: View {
    let state: AppState
    let intents: any AppIntents
    let navigation: any Navigation
    /// 打开着的表单：添加屏幕、某块屏的详情（渲染样例用初值）
    @State var sheet: ScreenSheet?
    @State private var explaining = false
    /// 选了要设为主屏、等确认的那块（渲染样例用初值）
    @State var confirmingMain: ScreenID?

    var body: some View {
        Form {
            Section { StatusHeader(state: state, navigation: navigation) }
            let issues = Issue.all(state, intents)
            if !issues.isEmpty {
                Section { ForEach(issues) { IssueRow(issue: $0) } }
            }
            Section {
                ForEach(state.config.screens) { screen in
                    ScreenRow(screen: screen, watching: state.watchedScreen == screen.id,
                              enabled: Binding(get: { screen.enabled }, set: { intents.setScreenEnabled(screen.id, $0) }),
                              details: { sheet = .detail(screen.id) })
                }
                if state.config.screens.isEmpty {
                    Text("还没有屏幕").foregroundStyle(.secondary)
                }
            } header: {
                Text("屏幕")
            } footer: {
                HStack(alignment: .firstTextBaseline, spacing: MacTokens.Space.s) {
                    HStack(spacing: MacTokens.Space.xs) {
                        Text("同一时间只用到一块屏，用不到的可以关掉。").foregroundStyle(.secondary)
                        Button("为什么？") { explaining = true }
                            .buttonStyle(.link)
                            .popover(isPresented: $explaining, arrowEdge: .bottom) { WhyManyScreens() }
                    }
                    .font(.callout)
                    Spacer(minLength: MacTokens.Space.m)
                    Button { sheet = .add } label: { Label("添加屏幕…", systemImage: "plus") }
                        .disabled(state.config.screens.count >= ScreenConfig.limit)
                        .help(state.config.screens.count >= ScreenConfig.limit ? "最多 \(ScreenConfig.limit) 块" : "")
                }
                .padding(.top, MacTokens.Space.xs)
            }
            Section {
                LabeledContent {
                    // 设主屏立即生效、影响本机，先讲清代价再设；改回「不改」不用问
                    Picker("设为主屏", selection: Binding(get: { state.config.mainScreen }, set: { id in
                        if let id, id != state.config.mainScreen { confirmingMain = id } else { intents.setMainScreen(id) }
                    })) {
                        Text("不改").tag(ScreenID?.none)
                        Divider()
                        ForEach(state.config.screens) { Text($0.name).tag(ScreenID?.some($0.id)) }
                    }
                    .labelsHidden()
                    .fixedSize()
                } label: {
                    SettingLabel("设为主屏", detail: "常驻并作为主屏，每次连接直接进入", tile: MacTokens.IconTile.mainScreen)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: MacTokens.Size.settingsWidth)
        .fixedSize(horizontal: false, vertical: true)
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .add: AddScreenSheet(state: state, intents: intents) { self.sheet = nil }
            case .detail(let id): ScreenDetailSheet(id: id, state: state, intents: intents) { self.sheet = nil }
            }
        }
        .confirmationDialog(confirmingMain.flatMap { state.screen($0) }.map { "将「\($0.name)」设为主屏？" } ?? "",
                            isPresented: Binding(get: { confirmingMain != nil }, set: { if !$0 { confirmingMain = nil } })) {
            Button("设为主屏") {
                if let id = confirmingMain { intents.setMainScreen(id) }
                confirmingMain = nil
            }
        } message: {
            Text(MainScreenNotice.detail)
        }
    }
}

/// 设为主屏的代价：设置里确认时讲清楚（README「设为主屏」同一套说法）
enum MainScreenNotice {
    static let detail = """
        此屏将常驻并作为 Mac 的主屏，立即生效；UU远程 每次连接即进入此屏。

        影响：当前主屏上的窗口随即移至此屏；此后程序坞、新窗口、系统提示与锁屏登录框均显示于此屏，本机不可见。适用于未接显示器或仅远程使用的 Mac。

        原因：UU远程 在连接时选定主屏，Snug 仅能在连接后察觉，须预先设定。可随时在 App 资源库或菜单栏取消。
        """
}

/// 设置窗口上弹出的表单
enum ScreenSheet: Identifiable, Equatable {
    case add
    case detail(ScreenID)

    var id: String {
        switch self {
        case .add: "add"
        case .detail(let id): "detail/\(id.rawValue)"
        }
    }
}

/// 屏幕列表的一行：类别图标、名字、横竖·型号、「在看」、开关、ⓘ
private struct ScreenRow: View {
    let screen: ScreenConfig
    let watching: Bool
    @Binding var enabled: Bool
    let details: () -> Void

    var body: some View {
        HStack(spacing: MacTokens.Space.m) {
            SettingLabel(screen.name, detail: screen.summary, tile: MacTokens.IconTile.screen(symbol: screen.symbol))
            Spacer(minLength: MacTokens.Space.s)
            if watching {
                Label("在看", systemImage: "circle.fill")
                    .labelStyle(WatchingBadge())
            }
            Toggle("", isOn: $enabled).labelsHidden().toggleStyle(.switch)
            Button(action: details) { Image(systemName: "info.circle") }
                .buttonStyle(.borderless)
                .help("详情")
                .accessibilityLabel("\(screen.name) 详情")
        }
    }
}

/// 「在看」：绿点 + 字
private struct WatchingBadge: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: MacTokens.Space.xs) {
            configuration.icon.font(.system(size: 6)).foregroundStyle(MacTokens.Color.positive)
            configuration.title.font(.callout).foregroundStyle(.secondary)
        }
    }
}

/// 「为什么？」的气泡：多开的屏留给什么
private struct WhyManyScreens: View {
    var body: some View {
        VStack(alignment: .leading, spacing: MacTokens.Space.m) {
            Text("可以开几块屏").font(.headline)
            Text("UU远程 一次只让一台设备控制。多开的屏留给：").foregroundStyle(.secondary)
            reason("rectangle.portrait.rotate", "横竖切换", "同一台设备横竖各一块，转过来在 UU 里切")
            reason("arrow.left.arrow.right", "换设备", "另一台接管后直接选它的屏，不用改设置")
            Text("关着的屏远程时不建，UU 的屏幕列表也更短。").font(.callout).foregroundStyle(.secondary)
        }
        .padding(MacTokens.Space.l)
        .frame(width: MacTokens.Size.helpPopoverWidth, alignment: .leading)
    }

    private func reason(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: MacTokens.Space.s) {
            Image(systemName: symbol).foregroundStyle(MacTokens.Color.accent).frame(width: 20)
            VStack(alignment: .leading, spacing: MacTokens.Space.xxs) {
                Text(title).fontWeight(.medium)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

/// 顶部：此刻的状态；缺权限时主按钮「授权…」就在这里
private struct StatusHeader: View {
    let state: AppState
    let navigation: any Navigation

    var body: some View {
        let text = StatusText(state)
        HStack(spacing: MacTokens.Space.m) {
            StatusTile(state.accessibilityTrusted ? state.status.tile : MacTokens.IconTile.accessibility)
            VStack(alignment: .leading, spacing: MacTokens.Space.xs) {
                Text(text.headline).font(.headline)
                if let detail = text.detail { Text(detail).foregroundStyle(.secondary) }
            }
            Spacer(minLength: MacTokens.Space.m)
            if !state.accessibilityTrusted {
                Button("授权…") { navigation.openWelcome() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.vertical, MacTokens.Space.xs)
    }
}

private struct Issue: Identifiable {
    enum Action {
        case run(String, @MainActor () -> Void)
        /// 缺权限：「授权…」打开系统设置对应的隐私页（见 AuthorizeButton）
        case authorize(PermissionFlowPane)
    }

    let id: String
    let text: StatusText
    let action: Action?

    /// 需要用户处理的问题，和解决它的按钮（有的话）
    @MainActor
    static func all(_ state: AppState, _ intents: any AppIntents) -> [Issue] {
        var list: [Issue] = []
        if state.legacyAppRunning {
            list.append(Issue(id: "legacy", text: StatusText(headline: "旧版「UU远程伴侣」运行中", detail: "与 Snug 同时运行将相互干扰"),
                              action: .run("退出旧版", intents.quitLegacyApp)))
        }
        if let issue = state.loginItemIssue {
            list.append(Issue(id: "login", text: issue.text,
                              action: issue == .needsApproval ? .run("前往允许", intents.openLoginItemsSettings) : nil))
        }
        if state.config.screenshot, !state.screenRecordingTrusted {
            list.append(Issue(id: "screen-recording",
                              text: StatusText(headline: "截图需要\(PermissionName.screenRecording)权限", detail: "系统设置 › 隐私与安全性"),
                              action: .authorize(.screenRecording)))
        }
        if state.configSaveFailed {
            list.append(Issue(id: "config", text: StatusText(headline: "设置未保存", detail: "修改未生效，请重试"), action: nil))
        }
        return list
    }
}

/// 一个问题一行：警示图标、出了什么事、去哪里处理，右边是解决它的按钮
private struct IssueRow: View {
    let issue: Issue

    var body: some View {
        LabeledContent {
            switch issue.action {
            case .run(let title, let run): Button(title, action: run)
            case .authorize(let pane): AuthorizeButton(pane: pane)
            case nil: EmptyView()
            }
        } label: {
            HStack(spacing: MacTokens.Space.m) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(MacTokens.Color.warning)
                    .frame(width: MacTokens.Size.iconTile)
                VStack(alignment: .leading, spacing: MacTokens.Space.xxs) {
                    Text(issue.text.headline)
                    if let detail = issue.text.detail { Text(detail).font(.callout).foregroundStyle(.secondary) }
                }
            }
        }
    }
}

// MARK: 触控

struct TouchPage: View {
    let state: AppState
    let intents: any AppIntents

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(get: { state.config.gestures }, set: { intents.setGestures($0) })) {
                    SettingLabel("触控手势", detail: "单指滚动 · 长按右键 · Codex 左缘右滑", tile: MacTokens.IconTile.gestures)
                }
                LabeledContent {
                    ZoomSlider(steps: Binding(get: { state.config.zoomSteps }, set: { intents.setZoomSteps($0) }))
                } label: {
                    SettingLabel("字号放大", detail: "窗口放上来时默认放大的级数", tile: MacTokens.IconTile.zoom)
                }
                Toggle(isOn: Binding(get: { state.config.screenshot }, set: { intents.setScreenshot($0) })) {
                    SettingLabel("截图", detail: "小横条左侧的相机键 · 截当前窗口到剪贴板", tile: MacTokens.IconTile.screenshot)
                }
            } footer: {
                Text("只作用于手机和平板屏。电脑屏不翻译手势、不放大字号。")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
        .frame(width: MacTokens.Size.settingsWidth)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// 字号放大：系统「文字大小」那样的带刻度滑块，两端小 A、大 A，每档一格
private struct ZoomSlider: View {
    @Binding var steps: Int

    var body: some View {
        let range = AppConfig.zoomStepsRange
        Slider(value: Binding(get: { Double(steps) }, set: { steps = Int($0.rounded()) }),
               in: Double(range.lowerBound)...Double(range.upperBound), step: 1) {
            Text("字号放大")
        } minimumValueLabel: {
            Image(systemName: "textformat.size.smaller")
        } maximumValueLabel: {
            Image(systemName: "textformat.size.larger")
        }
        .labelsHidden()
        .frame(width: MacTokens.Size.zoomSliderWidth)
        .accessibilityValue(steps == 0 ? "不放大" : "+\(steps) 级")
    }
}

// MARK: 通用

struct GeneralPage: View {
    let state: AppState
    let intents: any AppIntents
    let navigation: any Navigation

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(get: { state.launchAtLogin }, set: { intents.setLaunchAtLogin($0) })) {
                    SettingLabel("开机启动", tile: MacTokens.IconTile.launchAtLogin)
                }
            }
            Section("权限") {
                LabeledContent {
                    if state.accessibilityTrusted { PermissionStatus(granted: true) } else { AuthorizeButton(pane: .accessibility) }
                } label: {
                    SettingLabel.accessibility
                }
                LabeledContent {
                    if state.screenRecordingTrusted { PermissionStatus(granted: true) } else { AuthorizeButton(pane: .screenRecording) }
                } label: {
                    SettingLabel.screenRecording
                }
            }
            UpdateSection(state: state, intents: intents, navigation: navigation)
            Section {
            } footer: {
                HStack {
                    Spacer()
                    Button("退出 Snug") { intents.quit() }
                        .help("还原窗口后退出")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: MacTokens.Size.settingsWidth)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: 窗口

/// 设置窗口：三个标签页各是一个 SwiftUI 视图。NSTabViewController 自己会让窗口标题跟着当前页走，
/// 高度跟着当前页的内容（切页、出现提示）变，左上角不动（实测）
@MainActor
final class SettingsWindowController {
    enum Tab: Int, CaseIterable {
        case screens, touch, general

        var title: String {
            switch self {
            case .screens: "屏幕"
            case .touch: "触控"
            case .general: "通用"
            }
        }

        var symbol: String {
            switch self {
            case .screens: "rectangle.on.rectangle"
            case .touch: "hand.point.up.left"
            case .general: "gearshape"
            }
        }
    }

    private let state: AppState
    private let intents: any AppIntents
    private weak var navigation: (any Navigation)?
    private var window: NSWindow?
    private var tabs: NSTabViewController?

    init(state: AppState, intents: any AppIntents, navigation: any Navigation) {
        self.state = state
        self.intents = intents
        self.navigation = navigation
    }

    /// display：从哪块屏的菜单栏打开的（见 NSWindow.bring）
    func show(_ tab: Tab = .screens, on display: DisplayID? = nil, activating: Bool = true) {
        if window == nil, let navigation {
            let tabs = NSTabViewController()
            tabs.tabStyle = .toolbar
            for tab in Tab.allCases {
                let view: AnyView = switch tab {
                case .screens: AnyView(ScreensPage(state: state, intents: intents, navigation: navigation))
                case .touch: AnyView(TouchPage(state: state, intents: intents))
                case .general: AnyView(GeneralPage(state: state, intents: intents, navigation: navigation))
                }
                tabs.addTabViewItem(Self.item(tab, view))
            }
            // 先选好页再建窗口：窗口按这一页的大小建，居中才是正的
            tabs.selectedTabViewItemIndex = tab.rawValue
            let w = NSWindow(contentViewController: tabs)
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.toolbarStyle = .preference
            w.isReleasedWhenClosed = false
            // 只在建好时居中：之后关了再开，还在用户拖到的地方
            w.center()
            self.tabs = tabs
            window = w
        } else {
            tabs?.selectedTabViewItemIndex = tab.rawValue
        }
        window?.bring(to: display)
        window?.present(activating: activating)
    }

    private static func item(_ tab: Tab, _ view: some View) -> NSTabViewItem {
        let hosting = NSHostingController(rootView: view)
        hosting.sizingOptions = [.preferredContentSize]
        hosting.title = tab.title   // 窗口标题跟着当前页走
        let item = NSTabViewItem(viewController: hosting)
        item.label = tab.title
        item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.title)
        return item
    }
}
