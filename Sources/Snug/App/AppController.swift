// AppController（取代旧的 Coordinator）：会话这条挂载点的主人。
// 持有感知器、RemoteSession、可选的虚拟屏模块、看门狗管理和配置；每 0.5s 一拍把观测交给会话层，
// 会话变化再交给功能模块。以后的增强（键盘避让、触控快捷栏……）也照这个方式挂在会话上。
// 全仓唯一写配置的地方；界面只读 state，意图走 AppIntents（见 AppController+Intents.swift）
import AppKit
import SnugCore
import SnugDisplays

@MainActor
final class AppController {
    static let tickInterval: TimeInterval = 0.5
    /// 连上这么久还读不到控制端名称，就在后台点一次 UU 的「显示主界面」
    static let nameWait: TimeInterval = 2

    let state = AppState()
    /// 用户从菜单或设置里点「退出」（由 AppDelegate 接到退出流程上）
    var onQuitRequested: (() -> Void)?

    let paths: SnugPaths
    let store: ConfigStore
    let scheduler = MainQueueScheduler()
    let driver: CGDisplayDriver
    let feature: VirtualDisplayFeature
    var session = RemoteSession()
    let sensor: any SignalSource
    let watchdog: WatchdogAgent?
    private let heartbeat: AppStateWriter
    private var tickTimer: Timer?
    private var heartbeatTimer: Timer?
    private var observers: [any NSObjectProtocol] = []
    private var lastTickAt: Date?
    private var unnamedSince: Date?
    private var mainWindowRequested = false

    var executor: DisplayExecutor { feature.executor }

    /// - store: 配置；--simulate / --stress 传一个不落盘的
    /// - watchdog: nil 表示不管理看门狗（调试运行或模拟）
    init(paths: SnugPaths, store: ConfigStore, sensor: any SignalSource, watchdog: WatchdogAgent?) {
        precondition(LaunchContext.mode.touchesDisplays, "只渲染、只读的模式（\(LaunchContext.mode)）不许建 AppController")
        self.paths = paths
        self.store = store
        self.sensor = sensor
        self.watchdog = watchdog
        driver = CGDisplayDriver(paths: paths)
        feature = VirtualDisplayFeature(
            executor: DisplayExecutor(driver: driver, scheduler: scheduler),
            settings: .init(config: store.config, physicalControlAvailable: CGDisplayDriver.physicalControlAvailable))
        heartbeat = AppStateWriter(url: paths.appState)
        state.config = store.config
        state.physicalControlAvailable = CGDisplayDriver.physicalControlAvailable
    }

    /// 开始监控。启动时先按磁盘记录把上次残留的状态收拾干净（恢复物理屏、还原布局）
    func start() {
        executor.onTopologyChange = { [weak self] date in self?.session.noteSelfInducedChange(at: date) }
        executor.onStateChange = { [weak self] in self?.publishDisplay() }
        sensor.start()
        watchdog?.sync(enabled: store.config.watchdogEnabled)
        executor.refresh()
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.executor.refresh() }
        })
        tickTimer = schedule(every: Self.tickInterval) { $0.tick() }
        heartbeatTimer = schedule(every: 1) { $0.secondTick() }
        tick()
        secondTick()
        Log.info("开始监控（虚拟屏\(store.config.virtualDisplayEnabled ? "已开" : "未开")\(store.config.paused ? "，已暂停" : "")）")
    }

    /// 停止监控（退出收尾前调用）。心跳照常写到进程退出：收尾可能要十几秒，
    /// 心跳一停，看门狗会以为主程序卡死而把它结束掉
    func stopMonitoring() {
        tickTimer?.invalidate()
        tickTimer = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
        sensor.stop()
    }

    // MARK: 每拍

    private func tick() {
        let now = scheduler.now
        if let last = lastTickAt, now.timeIntervalSince(last) > 1.5 {
            Log.warn(String(format: "主线程卡了 %.1fs", now.timeIntervalSince(last)))
        }
        lastTickAt = now
        let sample = sensor.sample(now: Date())
        let transitions = session.update(sample.signals, now: now)
        feature.handle(transitions, session: session)
        for t in transitions { Log.info("会话：\(Self.describe(t))") }
        requestNameIfSlow(sample.signals, now: now)
        publishSession(sample)
        publishDisplay()
    }

    /// 名称只用连接事件里带的那一份（不在主线程再读一遍 AX）。表格读不到（多半是 UU 主窗口没开）时，后台点一次「显示主界面」
    private func requestNameIfSlow(_ signals: UUSignals, now: Date) {
        guard session.isConnected, session.controller == nil, signals.controllers == nil, UUAccessibility.isTrusted else {
            if !session.isConnected {
                unnamedSince = nil
                mainWindowRequested = false
            }
            return
        }
        let since = unnamedSince ?? now
        unnamedSince = since
        if !mainWindowRequested, now.timeIntervalSince(since) >= Self.nameWait {
            mainWindowRequested = true
            sensor.requestMainWindow()
        }
    }

    private func secondTick() {
        let target = executor.target
        heartbeat.write(connected: session.isConnected, keepOnlyVirtualActive: target.profile != nil && target.keepOnlyVirtual)
        state.update(\.accessibilityTrusted, UUAccessibility.isTrusted)
        state.update(\.watchdogRunning, WatchdogAgent.isRunning(heartbeat: paths.watchdogHeartbeat))
    }

    // MARK: 发布

    func publishSession(_ sample: UUSample) {
        state.update(\.connection, session.isConnected ? .connected : (session.inEpisode ? .reconnecting : .idle))
        state.update(\.controller, session.controller)
        state.update(\.streamedDisplay, sample.streamingDisplay.map { StreamedDisplay(id: $0, name: Self.screenName($0)) })
    }

    func publishDisplay() {
        state.update(\.display, VirtualDisplayStatus(
            activeProfile: executor.currentProfile,
            physicalOff: executor.physicalOff,
            wedged: executor.wedged,
            breakerTripped: feature.breaker.tripped,
            suspendedByUser: session.suspendedByUser,
            issue: executor.lastError?.message,
            layoutPending: driver.hasLayoutSnapshot()))
    }

    func publishConfig() {
        state.update(\.config, store.config)
        feature.update(settings: .init(config: store.config, physicalControlAvailable: CGDisplayDriver.physicalControlAvailable),
                       session: session)
        publishDisplay()
    }

    // MARK: 小工具

    private func schedule(every seconds: TimeInterval, _ body: @escaping @MainActor (AppController) -> Void) -> Timer {
        // 加进 .common：菜单展开、窗口拖动、退出收尾（terminateLater）期间也照常走
        let timer = Timer(timeInterval: seconds, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                body(self)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    /// 屏幕在「显示器」设置里的名字；找不到（虚拟屏刚建好、被熄灭的屏）就用编号
    static func screenName(_ id: DisplayID) -> String {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        let screen = NSScreen.screens.first { ($0.deviceDescription[key] as? NSNumber)?.uint32Value == id }
        return screen?.localizedName ?? "显示器 #\(id)"
    }

    static func describe(_ t: SessionTransition) -> String {
        switch t {
        case .began(let c): "开始（控制端 \(c ?? "未知")）"
        case .resumed(let c): "重连上，仍是同一次远程（控制端 \(c ?? "未知")）"
        case .controllerChanged(let c): "控制端变为 \(c)"
        case .interrupted: "断开，等 \(Int(SessionEpisode.reconnectWindow))s 看会不会重连"
        case .ended: "结束"
        }
    }
}
