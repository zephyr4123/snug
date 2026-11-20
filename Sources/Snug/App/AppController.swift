// AppController：把远控的观测、会话层和屏幕调度接在一起。
// 每 0.5 秒一拍：适配器给出观测 → 会话层判断连没连、是不是同一次远程 → ScreenPlan 按配置算出要哪些屏，交给 DeskSet。
// 要翻译手势的屏在时开手势翻译，范围跟着那几块屏走。全仓唯一写配置的地方；界面只读 state，意图见 AppController+Intents
import AppKit
import SnugCore
import SnugSystem

/// 显式标 Sendable（主线程隔离的类本来就是）：意图协议要求 Sendable，而遵循写在另一个文件里，
/// 不在这里标的话编译器会警告「Sendable 须在类所在的文件里声明」
@MainActor
final class AppController: Sendable {
    static let tickInterval: TimeInterval = 0.5
    /// 每隔这么久核对一次各块屏上的窗口还在不在
    static let verifyInterval: TimeInterval = 2

    let state = AppState()
    let updater: Updater
    let desks: DeskSet
    /// App 资源库的统一数据源（手机、平板屏和电脑屏的资源库共用）。界面碰得到的系统入口只有 desks 和它
    let catalog: AppCatalog
    /// 手机、平板屏上的截图（小横条的相机键）
    let screenshots = Screenshots(system: ScreenshotService())
    /// 用户从菜单或设置里点「退出」（由 AppDelegate 接到退出流程上）
    var onQuitRequested: (() -> Void)?

    let store: ConfigStore
    /// --preview-screens：不等远程就建出开着的屏
    private let preview: Bool
    /// 登记的远控适配器，按登记顺序（两家同时报在场时归第一家）
    private let remotes = Remotes.all.map { $0.adapter.init() }
    private var session = RemoteSession()
    private let touch: TouchTap
    private var watcher: DisplayWatcher?
    private var tickTimer: Timer?
    private var lastTickAt: Date?
    private var lastVerifyAt = Date.distantPast
    /// 手势翻译此刻覆盖哪几块屏：变了才记日志
    private var gestureScreens: Set<ScreenID> = []
    /// 单调时钟的起点：系统改时间不会让「已经过了多久」算错
    private let anchor = (date: Date(), uptime: ProcessInfo.processInfo.systemUptime)

    init(paths: SnugPaths, preview: Bool = false) {
        self.preview = preview
        store = ConfigStore(url: paths.config)
        let devices = Self.loadDevices()
        let helper = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        let windows = WindowService()
        let apps = AppService()
        desks = DeskSet(displays: VirtualDisplayService(helper: helper), windows: windows, apps: apps,
                        arrangement: DisplayArrangementService(), paths: paths, defaultZoom: store.config.zoomSteps)
        catalog = AppCatalog(apps: apps, windows: windows, excluding: Set(remotes.flatMap(\.identity.bundleIDs)))
        touch = TouchTap(injectors: remotes.map(\.identity.injector))
        state.config = store.config
        state.previewing = preview
        state.devices = devices
        state.accessibilityTrusted = AX.isTrusted
        updater = Updater(state: state)
        AX.configureTimeout()
        // 选过的型号按机型库现在的数值来（机型库改过数值时跟着改），建屏前就定下来
        for screen in store.config.screens {
            let resolved = devices.resolve(screen.device)
            guard resolved != screen.device else { continue }
            changeConfig("「\(screen.name)」的型号 \(resolved.title) 按机型库更新") { config in
                if let i = config.screens.firstIndex(where: { $0.id == screen.id }) { config.screens[i].device = resolved }
            }
        }
        // 2.6.x 设的主屏只在远程时生效；改为常驻后，代价要在设置里看过确认框才算数。升上来先撤掉，同样在建屏前定下来
        if let current = Updater.current, let last = store.config.lastVersion {
            changeConfig("从 \(last) 升级：原先只在远程时生效的设为主屏改回「不改」（现为常驻，需在设置中重新选定）") {
                _ = $0.dropRemoteOnlyMain(running: current)
            }
        }
    }

    var now: Date { anchor.date.addingTimeInterval(ProcessInfo.processInfo.systemUptime - anchor.uptime) }

    /// 机型库随 App 发（Contents/Resources）。读不出来只是没有型号可选，还能自己填分辨率，屏照常按配置里的比例
    private static func loadDevices() -> DeviceCatalog {
        guard let url = Bundle.main.url(forResource: "device-models", withExtension: "json") else {
            Log.error("App 里没有机型库 device-models.json（打包漏了），型号只能自己填")
            return .empty
        }
        do {
            let devices = try DeviceCatalog(contentsOf: url)
            let counts = DeviceKind.allCases.map { kind in "\(kind.rawValue) \(devices.brands(in: [kind]).flatMap(\.models).count)" }
            Log.info("机型库：\(devices.brands.count) 段品牌、\(devices.models.count) 款机型（\(counts.joined(separator: "、"))）")
            return devices
        } catch {
            Log.error("机型库读不出来（\(url.path)）：\(error)；型号只能自己填")
            return .empty
        }
    }

    /// 开始监控。有权限的话先把上次没放回去的窗口放回去
    func start() {
        desks.onChange = { [weak self] desks in self?.desksChanged(desks) }
        desks.onGone = { [weak self] gone in self?.catalog.forget(gone) }
        touch.onCloseWindow = { [weak self] window in self?.desks.closePlaced(window: window) }
        touch.onSetSidebar = { [weak self] window, open in
            guard let self else { return }
            guard let id = self.state.desks.desks.first(where: { $0.value.placed?.window.key.id == window })?.key,
                  self.state.desks.desks[id]?.placed?.window.bundleID == Self.codexBundleID else {
                Log.warn("要调整侧边栏的 Codex 窗口 \(window) 已经不在这块屏上")
                return
            }
            Task {
                guard await self.desks.setSidebar(on: id, open: open) else {
                    Log.warn("屏（\(id)）上的 Codex 侧边栏没能\(open ? "展开" : "关闭")")
                    return
                }
                Log.info("在 Codex 窗口横向滑动：\(open ? "展开" : "关闭")侧边栏")
            }
        }
        screenshots.onChange = { [weak self] overlay in self?.screenshotChanged(overlay) }
        desks.onTopologyChange = { [weak self] in
            guard let self else { return }
            session.noteSelfInducedChange(at: now)
        }
        let watcher = DisplayWatcher { [weak self] in
            self?.desks.displaysChanged()
            self?.syncGestures()
        }
        watcher.start()
        self.watcher = watcher
        remotes.forEach { $0.start() }
        if state.accessibilityTrusted { desks.recover() }
        let timer = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // 加进 .common：菜单展开、窗口拖动期间也照常走
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
        tick()
        let enabled = store.config.screens.filter(\.enabled).map(\.name)
        Log.info("开始监控（开着的屏：\(enabled.isEmpty ? "没有" : enabled.joined(separator: "、"))，手势\(store.config.gestures ? "已开" : "已关")"
                 + "\(preview ? "，预览模式：不等远程直接建屏" : "")）")
    }

    /// 停止监控（退出收尾前调用）
    func stopMonitoring() {
        tickTimer?.invalidate()
        tickTimer = nil
        watcher?.stop()
        remotes.forEach { $0.stop() }
    }

    // MARK: 每拍

    private func tick() {
        let now = now
        if let last = lastTickAt, now.timeIntervalSince(last) > 1.5 {
            Log.warn(String(format: "主线程卡了 %.1fs", now.timeIntervalSince(last)))
        }
        lastTickAt = now
        refreshTrust()
        screenshots.expire()
        let wallClock = Date()
        handle(session.update(remotes.map { RemoteReading(remote: $0.identity, observation: $0.sample(wallClock: wallClock)) }, now: now))
        keepPointerOffSnugScreens()
        if now.timeIntervalSince(lastVerifyAt) >= Self.verifyInterval {
            lastVerifyAt = now
            desks.verifyPlacement()
            desks.checkReturns()
            desks.settleDisplays()
            refreshScreenRecording()
        }
        // 推流只有一路画面（UU 一次只让一台设备控制，V12），在推哪块屏看这次远程的归属方
        state.update(\.streamedDisplay, session.tracked?.observation.streamedDisplay)
    }

    /// 会话变化统一在这里落地（每拍和菜单的「立即结束」共用）
    private func handle(_ transitions: [SessionTransition]) {
        if transitions.contains(.ended) {
            // 远程结束先说一声一块屏都不要，再按「不在远程」重算（只剩常驻的主屏）。不先说「不要」的话，下一次在同一拍里
            // 开始时前后要的屏一样，上一次在手机上退出的屏会带进这一次。同一拍里先「不要」再「要」不会撤屏重建（DeskSet 排队时读的是最新结论）
            desks.setWishes([])
        }
        applyPlan()
        desks.setRemote(session.inEpisode)
        state.update(\.connection, session.isConnected ? .connected : (session.inEpisode ? .reconnecting : .idle))
        state.update(\.controllers, session.controllers)
        state.update(\.remoteName, session.owner?.displayName)
    }

    /// 断开后远控不再动指针，而 Snug 的屏要等重连窗口才撤。这十几秒里指针若停在 Snug 的屏上，
    /// 那块屏在本机看不见，就成了「鼠标找不回来」。等待期每拍看一眼：用户一动又可能滑回去；
    /// 只在断开与重连之间生效，连上马上停（issue #29）。设为主屏的那块除外：它常驻、远程结束也不撤，
    /// 指针留在上面正是设主屏的本意（重连后接着用），和撤屏时指针落到主屏一致
    private func keepPointerOffSnugScreens() {
        guard session.inEpisode, !session.isConnected else { return }
        for (id, desk) in state.desks.desks where id != store.config.mainScreen {
            guard let display = desk.display else { continue }
            Cursor.leave(display)
        }
    }

    /// 不等重连窗口，立即结束本次远程（菜单栏「立即结束本次远程」，issue #29）。
    /// 只在重连等待期里有意义：不在这段时间里时 session.endNow() 什么都不做
    func endSessionNow() {
        guard let change = session.endNow() else { return }
        handle([change])
    }

    /// 按此刻的配置和会话算出要哪些屏，交给 DeskSet（结论没变就什么都不做）
    func applyPlan() {
        desks.setWishes(ScreenPlan.wishes(config: store.config, remote: session.inEpisode, trusted: state.accessibilityTrusted, preview: preview))
    }

    /// 权限是用户在系统设置里给的，随时会变：刚给上时把上次没放回去的窗口放回去
    private func refreshTrust() {
        let trusted = AX.isTrusted
        guard trusted != state.accessibilityTrusted else { return }
        state.accessibilityTrusted = trusted
        Log.info("辅助功能权限：\(trusted ? "已授权" : "被收回")")
        if trusted { desks.recover() }
    }

    /// 录屏权限也是用户在系统设置里给的：开着截图键时每两秒对一次（不跟着每拍去读 TCC），变了记一笔
    func refreshScreenRecording() {
        guard store.config.screenshot else { return }
        let trusted = screenshots.trusted
        guard trusted != state.screenRecordingTrusted else { return }
        state.screenRecordingTrusted = trusted
        Log.info("录屏权限：\(trusted ? "已授权" : "未授权")")
    }

    // MARK: 屏

    private func desksChanged(_ desks: DeskSet.State) {
        state.desks = desks
        // 截图所在的屏没了：浮着的截图、裁剪中的、正给它截的一并收掉，不然下次连上还盖着旧截图
        screenshots.dismiss(outside: Set(desks.desks.compactMap { $0.value.display == nil ? nil : $0.key }))
        syncGestures()
    }

    private func screenshotChanged(_ overlay: ScreenshotOverlay?) {
        state.screenshotOverlay = overlay
        state.screenshotScreen = screenshots.screen
        syncGestures()
    }

    /// 手势翻译只在要翻译手势的屏在、开着手势时运行；正在裁剪截图的那块屏除外（拖动是在画选区，不能翻译成滚动）。
    /// 每块屏一块范围，跟着那块屏走（换档、屏幕重排时 DisplayWatcher 也会调到这里）。
    /// Codex 窗口铺满屏时，向右横滑展开侧边栏、向左横滑关闭
    func syncGestures() {
        let cropping = state.screenshotOverlay?.isCropping == true ? state.screenshotScreen : nil
        let covered: [(id: ScreenID, region: TouchRegion)] = store.config.gestures ? state.desks.desks.compactMap { id, desk -> (id: ScreenID, region: TouchRegion)? in
            guard id != cropping, desk.behavior.touch, let display = desk.display else { return nil }
            // 窗口露着时才拦它的关闭按钮：列表盖着时那个位置是列表
            let bounds = CGDisplayBounds(display)
            let scale = ScreenFit.scale(screen: bounds.size)
            let sidebar = desk.listVisible ? nil : desk.placed.flatMap { placed -> SidebarSwipe? in
                guard placed.window.bundleID == Self.codexBundleID else { return nil }
                return TouchTranslator.sidebarSwipe(scale: scale, window: placed.window.key.id)
            }
            return (id, TouchRegion(screen: bounds, closeButton: desk.listVisible ? nil : desk.closeButton, sidebarSwipe: sidebar))
        } : []
        let ids = Set(covered.map(\.id))
        if ids != gestureScreens {
            gestureScreens = ids
            let names = ids.map(screenName).sorted().joined(separator: "、")
            let why = !store.config.gestures ? "（总开关关着）" : cropping.map { "（\(screenName($0)) 在裁剪截图）" } ?? ""
            Log.info("手势翻译范围：\(ids.isEmpty ? "没有屏" : names)\(why)")
        }
        state.update(\.gesturesFailed, !touch.setRegions(covered.map(\.region)))
    }

    /// Codex 的 macOS 版在「ChatGPT」App 里
    static let codexBundleID = "com.openai.codex"

    private func screenName(_ id: ScreenID) -> String {
        store.config.screens.first { $0.id == id }?.name ?? id.rawValue
    }
}
