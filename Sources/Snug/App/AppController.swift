// AppController：把 UU 的观测、会话层和手机屏接在一起。
// 每 0.5 秒一拍：感知器给出观测 → 会话层判断连没连、是不是同一次远程 → 算出「要不要手机屏」交给 PhoneDesk。
// 手机屏在时开手势翻译，范围跟着手机屏走。全仓唯一写配置的地方；界面只读 state，意图见 AppController+Intents
import AppKit
import SnugCore
import SnugSystem

@MainActor
final class AppController {
    static let tickInterval: TimeInterval = 0.5
    /// 每隔这么久核对一次手机屏上的窗口还在不在
    static let verifyInterval: TimeInterval = 2

    let state = AppState()
    let updater: Updater
    let desk: PhoneDesk
    let windows = WindowService()
    /// 用户从菜单或设置里点「退出」（由 AppDelegate 接到退出流程上）
    var onQuitRequested: (() -> Void)?

    let store: ConfigStore
    /// --preview-phone：不等手机连上就要手机屏
    private let previewPhone: Bool
    private let sensor = UUSensor()
    private var session = RemoteSession()
    private let touch = TouchTap()
    private var watcher: DisplayWatcher?
    private var tickTimer: Timer?
    private var lastTickAt: Date?
    private var lastVerifyAt = Date.distantPast
    /// 单调时钟的起点：系统改时间不会让「已经过了多久」算错
    private let anchor = (date: Date(), uptime: ProcessInfo.processInfo.systemUptime)

    init(paths: SnugPaths, previewPhone: Bool = false) {
        self.previewPhone = previewPhone
        store = ConfigStore(url: paths.config)
        let helper = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        desk = PhoneDesk(displays: PhoneDisplayService(helper: helper), windows: windows, paths: paths,
                         defaultZoom: store.config.zoomSteps)
        state.config = store.config
        state.accessibilityTrusted = AX.isTrusted
        updater = Updater(state: state)
        AX.configureTimeout()
        updater.onInstalled = { [weak self] in self?.quit() }
    }

    var now: Date { anchor.date.addingTimeInterval(ProcessInfo.processInfo.systemUptime - anchor.uptime) }

    /// 开始监控。有权限的话先把上次没放回去的窗口放回去
    func start() {
        desk.onChange = { [weak self] phone in self?.phoneChanged(phone) }
        desk.onTopologyChange = { [weak self] in
            guard let self else { return }
            session.noteSelfInducedChange(at: now)
        }
        let watcher = DisplayWatcher { [weak self] in
            self?.desk.displaysChanged()
            self?.syncGestures()
        }
        watcher.start()
        self.watcher = watcher
        sensor.start()
        if state.accessibilityTrusted { desk.recover() }
        let timer = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // 加进 .common：菜单展开、窗口拖动期间也照常走
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
        tick()
        Log.info("开始监控（手机屏\(store.config.phoneScreen ? "已开" : "已关")，手势\(store.config.gestures ? "已开" : "已关")"
                 + "\(previewPhone ? "，预览模式：不等手机直接加手机屏" : "")）")
    }

    /// 停止监控（退出收尾前调用）
    func stopMonitoring() {
        tickTimer?.invalidate()
        tickTimer = nil
        watcher?.stop()
        sensor.stop()
    }

    // MARK: 每拍

    private func tick() {
        let now = now
        if let last = lastTickAt, now.timeIntervalSince(last) > 1.5 {
            Log.warn(String(format: "主线程卡了 %.1fs", now.timeIntervalSince(last)))
        }
        lastTickAt = now
        refreshTrust()
        let sample = sensor.sample(now: Date())
        for t in session.update(sample.signals, now: now) { Log.info("会话：\(Self.describe(t))") }
        desk.setWanted(wantsPhoneScreen)
        if now.timeIntervalSince(lastVerifyAt) >= Self.verifyInterval {
            lastVerifyAt = now
            desk.verifyPlacement()
        }
        state.update(\.connection, session.isConnected ? .connected : (session.inEpisode ? .reconnecting : .idle))
        state.update(\.controller, session.controller)
        state.update(\.streamedDisplay, sample.streamingDisplay)
    }

    /// 要不要手机屏：开着总开关、有权限，这次远程的控制端不是电脑（见 RemoteSession.wantsPhoneScreen）
    private var wantsPhoneScreen: Bool {
        guard store.config.phoneScreen, state.accessibilityTrusted else { return false }
        return previewPhone || session.wantsPhoneScreen(now: now)
    }

    /// 权限是用户在系统设置里给的，随时会变：刚给上时把上次没放回去的窗口放回去
    private func refreshTrust() {
        let trusted = AX.isTrusted
        guard trusted != state.accessibilityTrusted else { return }
        state.accessibilityTrusted = trusted
        Log.info("辅助功能权限：\(trusted ? "已授权" : "被收回")")
        if trusted { desk.recover() }
    }

    // MARK: 手机屏

    private func phoneChanged(_ phone: PhoneDesk.State) {
        state.phone = phone
        syncGestures()
    }

    /// 手势翻译只在手机屏在、并且开着手势时运行；范围跟着手机屏
    func syncGestures() {
        let region = state.phone.display.map(CGDisplayBounds)
        guard store.config.gestures, let region else {
            if touch.isRunning { touch.stop() }
            touch.setRegion(nil)
            state.update(\.gesturesFailed, false)
            return
        }
        touch.setRegion(region)
        if !touch.isRunning { state.update(\.gesturesFailed, !touch.start()) }
    }

    static func describe(_ t: SessionTransition) -> String {
        switch t {
        case .began(let c): "开始（控制端 \(c ?? "读不到名字")）"
        case .resumed(let c): "重连上，仍是同一次远程（控制端 \(c ?? "读不到名字")）"
        case .controllerChanged(let c): "控制端变为 \(c)"
        case .interrupted: "断开，等 \(Int(SessionEpisode.reconnectWindow))s 看会不会重连"
        case .ended: "结束"
        }
    }
}
