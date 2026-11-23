// 电脑屏的 App 资源库：Mac 样式的窗口，从菜单栏的「App 资源库」打开，在哪块电脑屏的菜单栏点就在哪块屏上开、往哪块屏放。
// 电脑屏没有小横条；已经开在别的屏上的窗口不会自己过来，点程序坞只是把它在原来的屏上提到前面（V9），
// 远端的人看不见别的屏、拖不了窗口，靠这里一键拉过来。
// 左栏「运行中 / 全部 App」；每个窗口标出现在在哪块屏，「放到这块屏」交给这块屏的意图（电脑屏只挪过来居中，不铺满、不调字号），
// 挪过来的「还原」放回原处（远端的人一样拖不回去）。
// 数据和屏上的资源库共用 AppCatalog，窗口在哪块屏（WindowSpot）也从那里读；窗口没最小化时才要它刷新
import AppKit
import SnugCore
import SnugSystem
import SwiftUI

@MainActor
@Observable
final class LibraryModel {
    enum Source: Hashable {
        case running, all
    }

    /// 往哪块屏放
    var target: ScreenID?
    var source = Source.running
    var query = ""
}

struct LibraryView: View {
    let state: AppState
    let catalog: AppCatalog
    @Bindable var model: LibraryModel
    let place: (WindowInfo) -> Void
    let putBack: (WindowInfo) -> Void
    let open: (AppInfo) -> Void

    private var targetDisplay: DisplayID? { model.target.flatMap { state.desks.desks[$0]?.display } }
    private var targetName: String? { model.target.flatMap { state.screen($0)?.name } }

    var body: some View {
        NavigationSplitView {
            List(selection: $model.source) {
                Label("运行中", systemImage: "macwindow").badge(withWindows.count).tag(LibraryModel.Source.running)
                Label("全部 App", systemImage: "square.grid.2x2").badge(catalog.installed.count).tag(LibraryModel.Source.all)
            }
            .navigationSplitViewColumnWidth(MacTokens.Size.librarySidebar)
        } detail: {
            Group {
                switch model.source {
                case .running: running
                case .all: all
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) { banner }
            .navigationTitle("App 资源库")
            .navigationSubtitle(targetName.map { "放到「\($0)」" } ?? "电脑屏都不在")
        }
        .searchable(text: $model.query, placement: .toolbar, prompt: "搜索")
        .frame(minWidth: MacTokens.Size.LibraryWindow.width, minHeight: MacTokens.Size.LibraryWindow.height)
    }

    private var query: String { model.query.trimmingCharacters(in: .whitespaces) }

    /// 电脑屏没有面板：这块屏正在做的事、出的问题（放不过来、屏没好）写在列表上面，下一个动作开始时清掉
    @ViewBuilder private var banner: some View {
        let desk = model.target.flatMap { state.desks.desks[$0] }
        if let work = desk?.work {
            HStack(spacing: MacTokens.Space.s) {
                ProgressView().controlSize(.small)
                Text(work.libraryText).foregroundStyle(.secondary)
                Spacer()
            }
            .bannerStyle()
        } else if let notice = desk?.notice {
            HStack(alignment: .firstTextBaseline, spacing: MacTokens.Space.s) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(MacTokens.Color.warning)
                Text(notice.text.headline)
                if let detail = notice.text.detail { Text(detail).foregroundStyle(.secondary) }
                Spacer()
            }
            .bannerStyle()
        }
    }

    /// 有窗口的才列：电脑屏上要的是把窗口拉过来，没窗口的 App 在「全部 App」里点开
    private var withWindows: [RunningApp] { catalog.running.filter { !$0.windows.isEmpty } }

    @ViewBuilder private var running: some View {
        // 搜索：App 名对上的整个 App、标题对上的窗口各自列出
        let apps: [RunningApp] = query.isEmpty ? withWindows : {
            let found = AppList.search(query, installed: [], running: withWindows)
            let ids = Set(found.apps.map(\.bundleID))
            let windows = Set(found.windows.map(\.key))
            return withWindows.compactMap { app in
                if ids.contains(app.app.bundleID) { return app }
                var only = app
                only.windows = app.windows.filter { windows.contains($0.key) }
                return only.windows.isEmpty ? nil : only
            }
        }()
        if !catalog.loaded {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if apps.isEmpty {
            ContentUnavailableView(query.isEmpty ? "没有正在运行的 App" : "无结果", systemImage: "macwindow")
        } else {
            List {
                ForEach(apps) { app in
                    Section {
                        ForEach(app.windows) { window in windowRow(window).listRowSeparator(.hidden) }
                    } header: {
                        HStack(spacing: MacTokens.Space.s) {
                            Image(nsImage: catalog.icon(for: app.app)).resizable().frame(width: MacTokens.Size.libraryRowIcon, height: MacTokens.Size.libraryRowIcon)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(app.app.name).font(.headline).foregroundStyle(.primary)
                                Text(app.windowSummary).font(.callout).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private func windowRow(_ window: WindowInfo) -> some View {
        let spot = catalog.spots[window.key] ?? .hidden
        let here = targetDisplay.map { spot == .shown($0) } == true
        // 在这块屏的全屏空间里：「放到这块屏」会退出全屏、挪到眼前，按钮照实说
        let hiddenFullScreen = targetDisplay.map { spot == .fullScreen($0) } == true && !window.minimized
        // Snug 挪过来、还记着原处的：在这块屏上就能还原（在这块屏上直接开的窗口没有原处可回）
        let restorable = model.target.flatMap { state.desks.desks[$0]?.brought.contains(window.key) } == true
        return HStack(spacing: MacTokens.Space.s) {
            Image(systemName: "macwindow").foregroundStyle(.secondary)
            Text(window.displayTitle).lineLimit(1)
            Spacer(minLength: MacTokens.Space.m)
            Text(locationText(window, spot, here: here, hiddenFullScreen: hiddenFullScreen)).font(.callout).foregroundStyle(.secondary)
            if !here {
                Button(hiddenFullScreen ? "退出全屏" : "放到这块屏") { place(window) }
                    .disabled(targetDisplay == nil || state.desks.closing.contains(window.key))
            } else if restorable {
                Button("还原") { putBack(window) }
                    .disabled(state.desks.closing.contains(window.key))
            }
        }
        .frame(minHeight: MacTokens.Size.rowMinHeight - MacTokens.Space.s)
    }

    /// 窗口在哪：这块屏（露着、或在它的全屏空间里）、别的 Snug 屏（写名字）、别的屏（写屏名）、已最小化；
    /// 别的屏上没露着的（别的桌面、全屏空间）远端看不见，写「不在当前桌面」
    private func locationText(_ window: WindowInfo, _ spot: WindowSpot, here: Bool, hiddenFullScreen: Bool) -> String {
        if here { return "在这块屏" }
        if window.minimized { return "已最小化" }
        if hiddenFullScreen { return "在这块屏 · 全屏" }
        guard case .shown(let display) = spot else { return "不在当前桌面" }
        if let name = state.screenID(on: display).flatMap({ state.screen($0)?.name }) { return "在「\(name)」" }
        return CGDisplayIsBuiltin(display) != 0 ? "在内建屏" : "在「\(Screens.name(of: display))」"
    }

    @ViewBuilder private var all: some View {
        let apps = query.isEmpty ? catalog.installed.map(\.app) : AppList.search(query, installed: catalog.installed, running: []).apps
        if catalog.installed.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: MacTokens.Size.libraryGridItem), spacing: MacTokens.Space.m)], spacing: MacTokens.Space.l) {
                    ForEach(apps, id: \.bundleID) { app in
                        Button { open(app) } label: {
                            VStack(spacing: MacTokens.Space.xs) {
                                Image(nsImage: catalog.icon(for: app)).resizable().frame(width: MacTokens.Size.libraryGridIcon, height: MacTokens.Size.libraryGridIcon)
                                Text(app.name).font(.callout).lineLimit(1)
                                Circle().fill(.secondary).frame(width: 4, height: 4).opacity(catalog.running(app) == nil ? 0 : 1)
                            }
                            .frame(maxWidth: MacTokens.Size.libraryGridItem)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(targetDisplay == nil)
                    }
                }
                .padding(MacTokens.Space.xl)
            }
        }
    }
}

private extension View {
    func bannerStyle() -> some View {
        font(.callout)
            .padding(.horizontal, MacTokens.Space.l)
            .padding(.vertical, MacTokens.Space.s)
            .background(.bar)
    }
}

private extension Desk.Work {
    /// 资源库窗口上的进度：电脑屏只有打开 App、挪过来、放回去三件事
    var libraryText: String {
        switch self {
        case .opening(let app): "正在打开 \(app.name)…"
        case .placing(let window): "正在把 \(window.app) 挪过来…"
        case .puttingBack: "正在放回原处…"
        default: "请稍候…"
        }
    }
}

/// 资源库窗口：一个，开在要放的那块屏上；从打开到关掉一直跟着那块屏
@MainActor
final class LibraryWindowController: NSObject, NSWindowDelegate {
    private let state: AppState
    private let catalog: AppCatalog
    /// 往哪块屏放就交给哪块屏的意图，和屏上的面板走同一个入口
    private let intents: (ScreenID) -> any TouchIntents
    private let model = LibraryModel()
    private var window: NSWindow?
    /// 每打开一次、关掉一次都换一个代号：跟踪用的观察登记触发时代号对不上就不再续，不用去猜窗口还开没开着
    private var generation = 0
    private static let owner = "library"

    init(state: AppState, catalog: AppCatalog, intents: @escaping (ScreenID) -> any TouchIntents) {
        self.state = state
        self.catalog = catalog
        self.intents = intents
    }

    /// clicked：点菜单栏图标时那块屏。是电脑屏就往它放，不然往 UU 正在推的那块电脑屏、再不然第一块就绪的电脑屏。
    /// 一块都没有就不开：菜单项能不能点是展开那一刻算的，点下去之前远程可能刚好结束、电脑屏可能刚被关掉
    func show(on clicked: DisplayID?) {
        let ready = state.libraryScreens
        let onClicked = clicked.flatMap { state.screenID(on: $0) }.flatMap { ready.contains($0) ? $0 : nil }
        let watched = state.watchedScreen.flatMap { ready.contains($0) ? $0 : nil }
        let name = { (id: ScreenID) in "「\(self.state.screen(id)?.name ?? id.rawValue)」" }
        let from = clicked.map { "display \($0)" } ?? "认不出的屏"
        guard let target = onClicked ?? watched ?? ready.first, let display = state.desks.desks[target]?.display else {
            Log.info("App 资源库：在\(from)的菜单栏点的，没有就绪的电脑屏，不开窗口")
            return
        }
        Log.info("App 资源库：在\(from)的菜单栏点的，就绪的电脑屏 \(ready.map(name).joined(separator: "、"))，往\(name(target))（display \(display)）放")
        model.target = target
        let window = self.window ?? makeWindow()
        // 开在要放的那块屏上：远端的人看得见
        if let screen = Screens.screen(for: display) {
            window.center(on: screen)
        } else {
            window.center()
        }
        window.present(activating: true)
        generation += 1
        follow(generation)
    }

    private func makeWindow() -> NSWindow {
        let view = LibraryView(state: state, catalog: catalog, model: model,
                               place: { [weak self] window in
                                   guard let self, let target = model.target else { return }
                                   intents(target).pull(window)
                               },
                               putBack: { [weak self] window in
                                   guard let self, let target = model.target else { return }
                                   intents(target).putBack(window.key)
                               },
                               open: { [weak self] app in
                                   guard let self, let target = model.target else { return }
                                   intents(target).open(app)
                               })
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.title = "App 资源库"
        window.setContentSize(NSSize(width: MacTokens.Size.LibraryWindow.width, height: MacTokens.Size.LibraryWindow.height))
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.window = window
        return window
    }

    /// 从打开到关掉一直跟着要放的那块屏，最小化了也跟（见 update）
    private func follow(_ generation: Int) {
        guard generation == self.generation else { return }
        withObservationTracking {
            update()
        } onChange: { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.follow(generation) } }
        }
    }

    /// 那块屏撤掉了（远程结束、关了开关）：窗口会被系统挪到别的屏上，在那里用不到，跟着关掉。
    /// 主动打开的窗口也能在本机使用，刷新只取决于窗口是否最小化。
    private func update() {
        guard let target = model.target, state.desks.desks[target]?.display != nil else {
            Log.info("App 资源库要放的那块屏（\(model.target.map { "\($0)" } ?? "没有")）撤掉了，关掉资源库窗口")
            generation += 1
            // 不在观察登记里关：关窗口会当场回调 windowWillClose
            DispatchQueue.main.async { [weak self] in self?.window?.close() }
            return
        }
        let source = model.source
        if window?.isMiniaturized == false {
            // 这块屏正在放窗口、打开 App：同屏上的面板，这时不为它刷（和搬窗口排同一条队）
            catalog.want(Self.owner, busy: state.desks.desks[target]?.work != nil, spots: source == .running)
        } else {
            catalog.release(Self.owner)
        }
    }

    func windowWillClose(_ notification: Notification) {
        generation += 1
        catalog.release(Self.owner)
    }

    // 最小化、还原不经过 AppState，观察登记看不到，在这里补一次
    func windowDidMiniaturize(_ notification: Notification) { update() }
    func windowDidDeminiaturize(_ notification: Notification) { update() }
}
