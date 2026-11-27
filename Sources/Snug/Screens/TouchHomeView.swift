// 手机、平板屏上的「App 资源库」：盖住整块屏（连这块屏上的菜单栏一起），看起来像手机上的原生 App。每块屏一份，只管这块屏。
// 竖屏（宽 < 高）一栏：
//   顶部固定一行：左边返回键（放着窗口时才有，那一行一直留着，有没有返回键内容都不跳），右边「退出这块屏」「型号」；
//   标题和搜索框跟着列表滚走，分段控件「运行中 / 全部」滚到顶就停住、一直看得见，滚回顶部时页眉完整恢复。
//   - 运行中：在跑的 App，窗口挂在各自的 App 下（见 TouchAppCard）。放着窗口时它的 App 单列在最上面「当前 App」，其余在「其他 App」
//   - 全部：本机所有 App 的图标网格，按字典序，正在运行的下方有圆点
// 横屏（手机横拿、平板横屏）两栏：高度只有五六百点，左边 App 列表（小标题、搜索、分段控件），右边选中 App 的窗口，不用上下来回翻。
// 平板屏右上角约 45 点压着 UU 的圆形菜单按钮（V6），右上角的按钮往左让开（读环境值 topTrailingClear，搜索页、型号页同样）。
// - 搜索：见 TouchSearchPage；型号：见 TouchModelPage；分辨率（从型号页进）：见 TouchResolutionPage
// - 退出这块屏：页眉里再问一次，讲明窗口会还原、下次远程恢复
// - 取消主屏：只在设为主屏的那块屏上有（主屏常驻，手机上要能一键改回），同样在页眉里再问一次
// - 正在打开、正在放、正在调整屏幕（换型号、改分辨率）、正在退出：整屏讲明是哪个 App、哪个窗口、哪台设备；出了问题：顶部写明出了什么事、怎么办
// 每次回到列表、每次出了问题都从最上面看起。文字只用短词，图标全用 SF Symbols
import AppKit
import SnugCore
import SwiftUI

/// 盖在首页上的页面：搜索、型号、分辨率（从型号页进）。搜索、型号页有输入框，打开着时列表面板临时接收键盘（见 ScreenWindows），
/// query 是打开着的那一页的搜索词
@MainActor
@Observable
final class TouchPages {
    enum Page {
        case search, model, resolution
    }

    private(set) var page: Page?
    var query = ""

    var active: Bool { page != nil }
    /// 打开着的页有输入框，要接收键盘
    var needsKeys: Bool { page == .search || page == .model }
    /// 去掉首尾空格的搜索词：只打了空格算没搜
    var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

    func open(_ page: Page) {
        self.page = page
        query = ""
    }

    func close() {
        page = nil
        query = ""
    }
}

struct TouchHomeView: View {
    let screen: ScreenID
    let state: AppState
    let catalog: AppCatalog
    let pages: TouchPages
    let intents: any TouchIntents

    @State private var tab: Tab
    @State private var confirming: Confirm?
    /// 横屏时左栏选中的 App；没选过就跟着放着的窗口、再不然第一个
    @State private var selected: Int32?
    @Environment(\.topTrailingClear) private var topTrailingClear

    /// tab、confirming、selected：渲染样例用
    init(screen: ScreenID, state: AppState, catalog: AppCatalog, pages: TouchPages, intents: any TouchIntents,
         tab: Tab = .running, confirming: Confirm? = nil, selected: Int32? = nil) {
        self.screen = screen
        self.state = state
        self.catalog = catalog
        self.pages = pages
        self.intents = intents
        _tab = State(initialValue: tab)
        _confirming = State(initialValue: confirming)
        _selected = State(initialValue: selected)
    }

    enum Tab: CaseIterable, Identifiable {
        case running, all
        var id: Self { self }
        var title: String { self == .running ? "运行中" : "全部" }
    }

    /// 在等再点一下确认的：退出哪个 App、关哪个窗口、退出这块屏。同一时刻只有一个；
    /// 有了别的动作、换了页、收起了列表就作废，防误触要的是连着按两下
    enum Confirm: Equatable {
        case quit(Int32)
        case close(WindowKey)
        case dismissScreen
        case cancelMain
    }

    /// 退出这块屏的图标：右上角的按钮、确认卡和「正在退出」共用
    static let dismissSymbol = "rectangle.portrait.and.arrow.forward"
    /// 取消主屏的图标：和设置里「设为主屏」同一个
    static let mainSymbol = "menubar.rectangle"
    private static let top = "top"
    private var panel: PanelState { state.panel(screen) }
    private var config: ScreenConfig? { state.screen(screen) }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                switch pages.page {
                case .search: SearchPage(catalog: catalog, search: pages, panel: panel, intents: intents)
                case .model: TouchModelPage(screen: screen, state: state, pages: pages, intents: intents)
                case .resolution: TouchResolutionPage(screen: screen, state: state, pages: pages, intents: intents)
                case nil:
                    if geo.size.width > geo.size.height { split(width: geo.size.width) } else { home }
                }
                if let busy = BusyView.Content(panel.work, catalog: catalog, screen: config) {
                    BusyView(content: busy).transition(.opacity)
                }
            }
        }
        .animation(.easeOut(duration: MotionTokens.standard), value: panel.work)
        .background(TouchTokens.Color.background)
        .onChange(of: panel.listVisible) { confirming = nil }
        .onChange(of: panel.work) { confirming = nil }
        .onChange(of: tab) { confirming = nil }
        .onChange(of: pages.active) { confirming = nil }
    }

    private var home: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                backRow(proxy)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        header.id(Self.top)
                        SwiftUI.Section {
                            page
                                .padding(.horizontal, TouchTokens.Space.margin)
                                .padding(.top, TouchTokens.Space.xs)
                                .padding(.bottom, TouchTokens.Space.xxl)
                        } header: {
                            TabPicker(selection: $tab)
                                .padding(.horizontal, TouchTokens.Space.margin)
                                .padding(.vertical, TouchTokens.Space.m)
                                .background(TouchTokens.Color.background)
                        }
                    }
                }
                .scrollIndicators(.never)
                .onChange(of: panel.listVisible) { _, visible in
                    if visible { proxy.scrollTo(Self.top, anchor: .top) }
                }
                // 提示在页眉里：翻到下面时出了问题，滚回去让人看见
                .onChange(of: panel.notice) { _, notice in
                    if notice != nil { withAnimation { proxy.scrollTo(Self.top, anchor: .top) } }
                }
            }
        }
        .disabled(panel.work != nil)
    }

    /// 返回键那一行一直留着：有没有返回键，下面的内容都不跳。右边距由最右的图标按钮自己留（见 navButton）
    private func backRow(_ proxy: ScrollViewProxy?) -> some View {
        HStack {
            if let placed = panel.placed {
                BackButton(app: placed.window.app) { intents.returnToPlaced() }
            }
            Spacer(minLength: TouchTokens.Space.m)
            HStack(spacing: 0) {
                // 确认卡在页眉里：每次点都滚回去，翻到下面时再点也看得见
                if state.config.mainScreen == screen {
                    navButton(Self.mainSymbol, label: "取消主屏") {
                        confirming = .cancelMain
                        withAnimation { proxy?.scrollTo(Self.top, anchor: .top) }
                    }
                }
                navButton(Self.dismissSymbol, label: "退出这块屏") {
                    confirming = .dismissScreen
                    withAnimation { proxy?.scrollTo(Self.top, anchor: .top) }
                }
                navButton(config?.symbol ?? "iphone", label: "型号", atEdge: true) { pages.open(.model) }
            }
            .padding(.trailing, topTrailingClear)
        }
        .frame(height: TouchTokens.Size.touchTarget)
        .padding(.leading, TouchTokens.Space.margin)
        .padding(.top, TouchTokens.Space.m)
    }

    /// 顶部那一行右边的图标按钮：点按范围 touchTarget 见方，图标居中。
    /// 最右那个（atEdge）把这一行的右边距算进点按范围：图标贴着边距，和型号页的「完成」、搜索页的「取消」对齐，
    /// 点按范围伸到屏幕边上，图标左边不用留一大块空，两个图标才不会隔得太开
    private func navButton(_ symbol: String, label: String, atEdge: Bool = false, action: @escaping () -> Void) -> some View {
        let margin = atEdge ? TouchTokens.Space.margin : 0
        return Button(action: action) {
            Image(systemName: symbol)
                .font(TouchTokens.Font.headline.font.weight(.regular))
                .foregroundStyle(TouchTokens.Color.tint)
                .frame(width: TouchTokens.Size.touchTarget - margin, height: TouchTokens.Size.touchTarget, alignment: atEdge ? .trailing : .center)
                .padding(.trailing, margin)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: TouchTokens.Space.m) {
            Text("App").font(TouchTokens.Font.largeTitle.font)
            Button { pages.open(.search) } label: {
                SearchBar { Text("搜索 App").foregroundStyle(.secondary) }
            }
            .buttonStyle(PressableStyle())
            banners
        }
        .padding(.horizontal, TouchTokens.Space.margin)
        .padding(.top, TouchTokens.Space.xs)
    }

    /// 退出这块屏、取消主屏的确认，出了问题的提示
    @ViewBuilder private var banners: some View {
        if confirming == .cancelMain {
            Banner(symbol: Self.mainSymbol, tint: .indigo, headline: "取消主屏？", detail: "主屏改回 Mac，远程结束后撤掉此屏") {
                ConfirmButtons(title: "确定", confirming: $confirming, spacing: TouchTokens.Space.m) { intents.cancelMain() }
            }
        } else if confirming == .dismissScreen {
            // 屏留着的那种（只在启动时认屏的远控）：撤了再建它就选不到，退出只还原窗口
            Banner(symbol: Self.dismissSymbol, tint: .red, headline: "退出这块屏？",
                   detail: panel.staysOnDismiss ? "窗口还原，屏幕保留" : "窗口还原，下次远程时恢复") {
                // 间距和提示卡里的「稍后 / 强制退出」一样
                ConfirmButtons(title: "退出", confirming: $confirming, spacing: TouchTokens.Space.m) { intents.dismissScreen() }
            }
        } else if let notice = panel.notice {
            NoticeBanner(notice: notice, intents: intents)
        }
    }

    @ViewBuilder private var page: some View {
        switch tab {
        case .running: runningPage
        case .all: AllApps(catalog: catalog, quitting: panel.quitting, intents: intents)
        }
    }

    private var runningPage: some View {
        VStack(alignment: .leading, spacing: TouchTokens.Space.xxl) {
            if let placed = panel.placed {
                TitledSection("当前 App") { appCard(catalog.app(of: placed.window)) }
            }
            let others = catalog.running.filter { $0.pid != panel.placed?.window.key.pid }
            if !catalog.loaded {
                EmptyState(symbol: nil, text: "正在读取")
            } else if others.isEmpty {
                if panel.placed == nil { EmptyState(symbol: "square.grid.2x2", text: "没有正在运行的 App") }
            } else if panel.placed != nil {
                TitledSection("其他 App") { appCards(others) }
            } else {
                appCards(others)
            }
        }
    }

    private func appCards(_ apps: [RunningApp]) -> some View {
        LazyVStack(spacing: TouchTokens.Space.m) {
            ForEach(apps) { appCard($0) }
        }
    }

    private func appCard(_ app: RunningApp) -> some View {
        AppCard(app: app, panel: panel, onScreen: OnScreen(config), confirming: $confirming, icon: catalog.icon(for: app.app), intents: intents)
    }

    // MARK: 横屏两栏

    /// 左边 App 列表，右边选中 App 的窗口
    private func split(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            sideColumn.frame(width: (config?.device.kind ?? .phone).landscapeSidebar(in: width))
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                backRow(nil)
                ScrollView {
                    VStack(alignment: .leading, spacing: TouchTokens.Space.m) {
                        banners
                        detail
                    }
                    .padding(.horizontal, TouchTokens.Space.margin)
                    .padding(.vertical, TouchTokens.Space.m)
                }
                .scrollIndicators(.never)
            }
        }
        .disabled(panel.work != nil)
        .onChange(of: panel.listVisible) { _, visible in if visible { selected = nil } }
    }

    private var sideColumn: some View {
        VStack(alignment: .leading, spacing: TouchTokens.Space.m) {
            Text("App").font(TouchTokens.Font.headline.font.weight(.bold))
            Button { pages.open(.search) } label: {
                SearchBar { Text("搜索 App").foregroundStyle(.secondary) }
            }
            .buttonStyle(PressableStyle())
            TabPicker(selection: $tab)
            ScrollView {
                LazyVStack(spacing: TouchTokens.Space.xs) {
                    switch tab {
                    case .running: ForEach(catalog.running) { sideRow(running: $0) }
                    case .all: ForEach(catalog.installed) { sideRow(installed: $0.app) }
                    }
                }
            }
            .scrollIndicators(.never)
            .overlay {
                if !catalog.loaded || (tab == .all && catalog.installed.isEmpty) {
                    EmptyState(symbol: nil, text: "正在读取")
                } else if tab == .running, catalog.running.isEmpty {
                    EmptyState(symbol: "square.grid.2x2", text: "没有正在运行的 App")
                }
            }
        }
        .padding(.horizontal, TouchTokens.Space.margin)
        .padding(.top, TouchTokens.Space.margin)
    }

    /// 选中的 App：没选过就是放着的窗口的 App，再不然第一个
    private var shown: RunningApp? {
        let pid = selected ?? panel.placed?.window.key.pid
        if let pid, let app = catalog.running.first(where: { $0.pid == pid }) { return app }
        if let placed = panel.placed { return catalog.app(of: placed.window) }
        return catalog.running.first
    }

    private func sideRow(running app: RunningApp) -> some View {
        Button { selected = app.pid } label: {
            sideLabel(icon: catalog.icon(for: app.app), title: app.app.name, subtitle: app.windowSummary, chosen: shown?.pid == app.pid)
        }
        .buttonStyle(PressableStyle())
        .disabled(panel.quitting.contains(app.pid))
    }

    /// 全部 App：在跑的选中看窗口，没在跑的点了就打开
    private func sideRow(installed app: AppInfo) -> some View {
        let running = catalog.running(app)
        return Button {
            if let running { selected = running.pid } else { intents.open(app) }
        } label: {
            sideLabel(icon: catalog.icon(for: app), title: app.name, subtitle: running.map { "运行中 · \($0.windowSummary)" },
                      chosen: running != nil && shown?.pid == running?.pid)
        }
        .buttonStyle(PressableStyle())
    }

    private func sideLabel(icon: NSImage, title: String, subtitle: String?, chosen: Bool) -> some View {
        HStack(spacing: TouchTokens.Space.m) {
            AppIcon(image: icon, size: TouchTokens.Size.listIcon * 0.75)
            VStack(alignment: .leading, spacing: TouchTokens.Space.xxs) {
                Text(title).font(TouchTokens.Font.label.font).lineLimit(1)
                if let subtitle { Text(subtitle).font(TouchTokens.Font.caption.font).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, TouchTokens.Space.m)
        .frame(minHeight: TouchTokens.Size.touchTarget)
        .background(chosen ? TouchTokens.Color.tintFill : .clear, in: RoundedRectangle(cornerRadius: TouchTokens.Radius.control, style: .continuous))
        .contentShape(Rectangle())
    }

    @ViewBuilder private var detail: some View {
        if let app = shown {
            // 放着窗口的 App：那个窗口排第一（见 AppCatalog.app(of:)）
            appCard(panel.placed.flatMap { $0.window.key.pid == app.pid ? catalog.app(of: $0.window) : nil } ?? app)
            Text("点窗口放到这块屏上，铺满并放大字号").font(TouchTokens.Font.caption.font).foregroundStyle(.secondary)
                .padding(.horizontal, TouchTokens.Space.xs)
        } else if catalog.loaded {
            EmptyState(symbol: "square.grid.2x2", text: "没有正在运行的 App")
        }
    }
}


// MARK: 页眉

/// 分段控件：和 iOS 的一样，选中的那段浮起来
private struct TabPicker: View {
    @Binding var selection: TouchHomeView.Tab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(TouchHomeView.Tab.allCases) { tab in
                Button { selection = tab } label: {
                    Text(tab.title)
                        .font(TouchTokens.Font.label.font.weight(selection == tab ? .semibold : .medium))
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background {
                            if selection == tab {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(TouchTokens.Color.segment)
                                    .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(TouchTokens.Color.fill, in: RoundedRectangle(cornerRadius: TouchTokens.Radius.card, style: .continuous))
        .animation(.easeOut(duration: MotionTokens.fast), value: selection)
    }
}

/// 回到屏上的窗口：和 iPhone 左上角「‹ App 名」回到上一个 App 一样
private struct BackButton: View {
    let app: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: TouchTokens.Space.xs) {
                Image(systemName: "chevron.left").font(TouchTokens.Font.headline.font)
                Text(app).font(TouchTokens.Font.body.font.weight(.medium)).lineLimit(1)
            }
            .foregroundStyle(TouchTokens.Color.tint)
            .padding(.leading, TouchTokens.Space.l)
            .padding(.trailing, TouchTokens.Space.margin)
            .frame(height: TouchTokens.Size.touchTarget)
            .background(TouchTokens.Color.tint.opacity(0.12), in: Capsule())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("返回 \(app)")
    }
}

/// 出了什么事、怎么办；没退出的 App 给「稍后 / 强制退出」
private struct NoticeBanner: View {
    let notice: Desk.Notice
    let intents: any TouchIntents

    var body: some View {
        let text = notice.text
        Banner(symbol: "exclamationmark.circle.fill", tint: .orange, headline: text.headline, detail: text.detail) {
            if case .quitStalled(let app, let pid) = notice {
                HStack(spacing: TouchTokens.Space.m) {
                    PillButton(title: "稍后") { intents.dismissNotice() }
                    PillButton(title: "强制退出", destructive: true) { intents.forceQuit(pid: pid, app: app) }
                }
            }
        }
    }
}

/// 页眉里的一张卡：图标、一句话、补充说明，下面可以带按钮（提示、退出这块屏的确认）
private struct Banner<Actions: View>: View {
    let symbol: String
    let tint: Color
    let headline: String
    let detail: String?
    @ViewBuilder let actions: Actions

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: TouchTokens.Space.m) {
            Image(systemName: symbol).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: TouchTokens.Space.xs) {
                Text(headline).font(TouchTokens.Font.body.font.weight(.semibold))
                if let detail {
                    Text(detail).font(TouchTokens.Font.body.font).foregroundStyle(.secondary)
                }
                actions
            }
        }
        .font(TouchTokens.Font.body.font)
        .padding(TouchTokens.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

// MARK: 全部

/// 本机所有 App：图标网格，4 列，按字典序；正在运行的下方有圆点，正在退出的点不了
private struct AllApps: View {
    let catalog: AppCatalog
    let quitting: Set<Int32>
    let intents: any TouchIntents

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 4)

    var body: some View {
        if catalog.installed.isEmpty {
            EmptyState(symbol: nil, text: "正在读取")
        } else {
            let running = Dictionary(catalog.running.map { ($0.app.bundleID, $0.pid) }, uniquingKeysWith: { first, _ in first })
            LazyVGrid(columns: Self.columns, spacing: TouchTokens.Space.margin) {
                ForEach(catalog.installed) { item in
                    let pid = running[item.app.bundleID]
                    Button { intents.open(item.app) } label: {
                        VStack(spacing: TouchTokens.Space.s) {
                            AppIcon(image: catalog.icon(for: item.app), size: 72)
                            Text(item.app.name).font(TouchTokens.Font.label.font).lineLimit(1).frame(maxWidth: 116)
                            Circle()
                                .fill(.secondary)
                                .frame(width: 6, height: 6)
                                .opacity(pid == nil ? 0 : 1)
                                .padding(.top, -TouchTokens.Space.xs)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle())
                    .disabled(pid.map(quitting.contains) ?? false)
                }
            }
        }
    }
}

// MARK: 正在打开、正在放、正在调整屏幕、正在退出

/// 整屏讲明正在打开哪个 App、放哪个窗口、按哪台设备调整屏幕（换型号、改分辨率）、在退出这块屏。窗口挪好列表就收起，失败了回到列表、顶部写明原因
private struct BusyView: View {
    struct Content: Equatable {
        enum Art: Equatable {
            case icon(NSImage)
            case symbol(String)
        }

        let art: Art
        let title: String
        let subtitle: String?
        let status: String

        @MainActor
        init?(_ work: Desk.Work?, catalog: AppCatalog, screen: ScreenConfig?) {
            switch work {
            case .opening(let app):
                (art, title, subtitle, status) = (.icon(catalog.icon(for: app)), app.name, nil, "正在打开")
            case .placing(let window):
                (art, title, subtitle, status) = (.icon(catalog.icon(for: window)), window.app,
                                                  window.title.isEmpty ? nil : window.title, "正在打开")
            case .reshaping:
                (art, title, subtitle, status) = (.symbol(screen?.symbol ?? "iphone"), screen?.device.displayName ?? "",
                                                  screen?.sizeText, "正在调整屏幕")
            case .dismissing:
                (art, title, subtitle, status) = (.symbol(TouchHomeView.dismissSymbol), screen?.name ?? "", nil, "正在退出")
            default:
                return nil
            }
        }
    }

    let content: Content

    var body: some View {
        VStack(spacing: TouchTokens.Space.l) {
            switch content.art {
            case .icon(let image):
                AppIcon(image: image, size: TouchTokens.Size.listIcon * 2)
            case .symbol(let name):
                Image(systemName: name)
                    .font(.system(size: TouchTokens.Size.listIcon * 1.5, weight: .light))
                    .foregroundStyle(.secondary)
                    .frame(width: TouchTokens.Size.listIcon * 2, height: TouchTokens.Size.listIcon * 2)
                    .accessibilityHidden(true)
            }
            VStack(spacing: TouchTokens.Space.xs) {
                Text(content.title).font(TouchTokens.Font.headline.font).lineLimit(1)
                if let subtitle = content.subtitle {
                    Text(subtitle).font(TouchTokens.Font.body.font).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            VStack(spacing: TouchTokens.Space.s) {
                ProgressView()
                Text(content.status).font(TouchTokens.Font.label.font).foregroundStyle(.secondary)
            }
            .padding(.top, TouchTokens.Space.l)
        }
        .padding(.horizontal, TouchTokens.Space.section)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TouchTokens.Color.background)
    }
}
