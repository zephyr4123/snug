import CoreGraphics
import Foundation
@testable import SnugCore

/// 假屏幕和假窗口共用的流水账：检查动作的先后
final class Journal: Sendable {
    private let entries = Locked<[String]>([])
    func add(_ entry: String) { entries.withLock { $0.append(entry) } }
    var all: [String] { entries.withLock { $0 } }
    func clear() { entries.withLock { $0 = [] } }
    func index(of entry: String) -> Int? { all.firstIndex(of: entry) }
}

@MainActor
final class FakeDisplays: VirtualDisplays {
    /// 假屏的左上角（辅助功能坐标）和菜单栏高度：可放区域 = 这一档扣掉菜单栏和底部小横条
    nonisolated static let origin = CGPoint(x: 2000, y: 0)
    nonisolated static let menuBar: CGFloat = 25

    let journal: Journal
    var nextID: DisplayID = 100
    /// 接下来这么多次建屏失败
    var failuresLeft = 0
    /// 换档不成（帮手进程失败）：屏还是原来那一档
    var switchFails = false
    /// 换比例不成：屏还是原来的档位
    var reshapeFails = false
    /// 读不到可放区域（屏幕组合还在变）
    var areaUnavailable = false
    /// 加屏、撤屏时 macOS 的副作用（把窗口拉过去、挪走）
    var onCreate: (() -> Void)?
    var onRetire: (() -> Void)?
    /// 记下建屏、撤屏的时刻（检查「建好不到 2.5 秒不撤」）
    var clock: (() -> TimeInterval)?
    private(set) var createdAt: [DisplayID: TimeInterval] = [:]
    private(set) var retiredAt: [DisplayID: TimeInterval] = [:]
    /// 每块屏此刻是哪一档；建好时是基准宽度。设成别的值模拟系统自己改了模式
    var widths: [DisplayID: Int] = [:]
    /// 每块屏登记的是哪个比例的档位
    private(set) var fits: [DisplayID: ScreenFit] = [:]
    /// 别的屏此刻的模式。在 onCreate / onRetire 里改它，模拟 macOS 换屏幕组合时把别的屏拨回它记的模式
    var others: [DisplayID: ScreenMode] = [:]
    /// 别的屏此刻在哪（全局坐标）。在 onCreate / onRetire 里改它，模拟 macOS 给 Snug 的屏让地方时挪了别的屏
    var otherBounds: [DisplayID: CGRect] = [:]
    /// Snug 的屏被系统挪开了多少。在 onCreate / onRetire 里改它，模拟加撤屏时 macOS 连 Snug 的屏一起挪
    var nudged: [DisplayID: CGVector] = [:]
    /// 设模式不成（帮手失败）：屏还是被拨动后的模式
    var modeFails = false
    /// 释放后不下线（显示器睡着时要等唤醒）：goOffline 才真下线，onRetire 那时才发生
    var staysOnline = false
    private(set) var lingering: Set<DisplayID> = []
    /// 睡着的别的屏
    var asleep: Set<DisplayID> = []
    var mirrors: Set<DisplayID> = []

    init(journal: Journal) { self.journal = journal }

    /// 这一档的可放区域，和真的一样：整屏扣掉菜单栏和（跟着缩放的）底部小横条
    nonisolated static func area(width: Int, fit: ScreenFit = .standard) -> CGRect {
        let size = fit.size(width: width)
        let bar = ScreenFit.homeBarHeight(screen: size)
        return CGRect(x: origin.x, y: origin.y + menuBar, width: size.width, height: size.height - menuBar - bar)
    }

    /// 每块屏建的时候用的身份
    private(set) var specs: [DisplayID: ScreenSpec] = [:]

    func create(_ spec: ScreenSpec, _ fit: ScreenFit) async throws -> DisplayID {
        journal.add("create")
        if failuresLeft > 0 {
            failuresLeft -= 1
            throw ScreenError.neverOnline
        }
        nextID += 1
        specs[nextID] = spec
        createdAt[nextID] = clock?()
        widths[nextID] = fit.baseWidth
        fits[nextID] = fit
        onCreate?()
        return nextID
    }

    func retire(_ id: DisplayID) async -> Bool {
        journal.add("retire \(id)")
        retiredAt[id] = clock?()
        widths[id] = nil
        fits[id] = nil
        guard !staysOnline else {
            lingering.insert(id)
            return false
        }
        onRetire?()
        return true
    }

    /// 释放后迟迟没下线的屏这时下线（显示器醒了）
    func goOffline(_ id: DisplayID) {
        lingering.remove(id)
        onRetire?()
    }

    func isOnline(_ id: DisplayID) -> Bool { widths[id] != nil || lingering.contains(id) }

    func isMirrored(_ id: DisplayID) -> Bool { mirrors.contains(id) }

    func reshape(_ id: DisplayID, to fit: ScreenFit) async -> Bool {
        journal.add("reshape \(id) \(fit)")
        guard !reshapeFails, widths[id] != nil else { return false }
        fits[id] = fit
        widths[id] = fit.baseWidth
        return true
    }

    func fit(_ id: DisplayID) -> ScreenFit? { fits[id] }

    func width(_ id: DisplayID) -> Int? { widths[id] }

    /// 和真的一样：不是这块屏登记的档位就换不成（帮手找不到这一档）
    func setWidth(_ id: DisplayID, _ width: Int) async {
        journal.add("width \(id) \(width)")
        guard !switchFails, fits[id]?.widths.contains(width) == true else { return }
        widths[id] = width
    }

    /// 第几块屏（按编号）往右排：第一块在 origin，后面的接着往右放，各不重叠
    private func origin(of id: DisplayID) -> CGPoint {
        let before = widths.keys.filter { $0 < id }.count
        let nudge = nudged[id] ?? .zero
        return CGPoint(x: Self.origin.x + CGFloat(before) * 4000 + nudge.dx, y: Self.origin.y + nudge.dy)
    }

    func bounds(_ id: DisplayID) -> CGRect? {
        guard let width = widths[id], let fit = fits[id] else { return nil }
        return CGRect(origin: origin(of: id), size: fit.size(width: width))
    }

    func windowArea(_ id: DisplayID, withHomeBar: Bool) -> CGRect? {
        guard !areaUnavailable, let width = widths[id], let fit = fits[id] else { return nil }
        var area = Self.area(width: width, fit: fit)
        area.origin.x = origin(of: id).x
        if !withHomeBar { area.size.height += ScreenFit.homeBarHeight(screen: fit.size(width: width)) }
        return area
    }

    /// 假主屏：左上角在原点，1512 宽，扣掉菜单栏
    nonisolated static let main = CGRect(x: 0, y: 25, width: 1512, height: 957)
    /// 主屏是这块假屏（设主屏后）：可放区域在它上面
    var mainOn: DisplayID?
    func mainArea() -> CGRect? { mainOn.flatMap(bounds) ?? Self.main }

    func otherDisplays() -> [OtherDisplay] {
        others.sorted { $0.key < $1.key }.map { OtherDisplay(id: $0.key, name: "屏 \($0.key)", mode: $0.value, bounds: otherBounds[$0.key] ?? .zero, asleep: asleep.contains($0.key)) }
    }

    func setMode(_ id: DisplayID, _ mode: ScreenMode, permanently: Bool) async {
        journal.add("mode \(id) \(mode)\(permanently ? " 永久" : "")")
        guard !modeFails, others[id] != nil else { return }
        others[id] = mode
    }
}

/// 假窗口：记住每个窗口的位置、是否全屏、是否最小化、字号级数
final class FakeWindows: WindowControl {
    struct Window: Sendable {
        var frame: CGRect
        var fullScreen = false
        /// 切全屏时换过去的另一个样子：全屏时是平时的位置，平时是整屏大小（和真的一样，全屏时读到的是整屏）
        var otherFrame: CGRect?
        var minimized = false
        /// App 把窗口藏起来了（被隐藏、关成了隐藏）：还在，但不在屏上
        var hidden = false
        var zoom = 0
        /// 到这个时刻才出现在屏上（App 刚启动、窗口还没画出来）
        var shownFrom: TimeInterval = 0
        /// 列表、捕获新窗口时报出来的样子
        var info: WindowInfo?
    }

    let journal: Journal
    private let state = Locked<[WindowKey: Window]>([:])
    private let blocked = Locked(false)
    private let movesBlocked = Locked(false)
    private let zoomBlocked = Locked(false)
    private let movesIgnored = Locked(false)
    private let grows = Locked(false)
    private let minSizes = Locked<[WindowKey: CGSize]>([:])
    private let moveHook = Locked<(@Sendable (WindowKey) -> Void)?>(nil)
    private let refusal = Locked<(@Sendable (WindowKey, CGRect) -> Bool)?>(nil)
    private let asking = Locked<Asking?>(nil)
    private let closeReactions = Locked<[WindowKey: CloseReaction]>([:])
    /// 判断窗口出没出现在屏上的时钟（见 Window.shownFrom）
    let clock = Locked<(@Sendable () -> TimeInterval)?>(nil)
    /// 设了就在每次挪窗口、发按键时记一下此刻还原记录在不在（检查「先记账再动手」）
    let ledger: URL?

    init(journal: Journal, ledger: URL? = nil) {
        self.journal = journal
        self.ledger = ledger
    }

    /// App 没响应（或辅助功能权限被收回）：窗口还在，但读不到、挪不动、发不了按键；传 false 恢复
    func block(_ on: Bool = true) { blocked.withLock { $0 = on } }
    /// 只是挪不动（App 卡在改窗口大小上），别的照常；传 false 恢复
    func blockMoves(_ on: Bool = true) { movesBlocked.withLock { $0 = on } }
    /// App 不认挪动（不退全屏、拒绝辅助功能改位置）：读得到，挪了没反应；传 false 恢复
    func ignoreMoves(_ on: Bool = true) { movesIgnored.withLock { $0 = on } }
    /// 只是字号按键发不出去（找窗口那一下刚好超时），别的照常；传 false 恢复
    func blockZoom(_ on: Bool = true) { zoomBlocked.withLock { $0 = on } }
    /// 像终端那样：调字号时保持行列数，窗口跟着变大
    func growOnZoom() { grows.withLock { $0 = true } }
    /// 像系统设置、Safari 那样：App 限定了最小尺寸，再小也压不下去
    func setMinSize(_ key: WindowKey, width: CGFloat = 0, height: CGFloat = 0) {
        minSizes.withLock { $0[key] = CGSize(width: width, height: height) }
    }
    /// 只有某几次挪不动（比如挪到某块屏上的那一下刚好超时），别的照常
    func refuseMoves(_ when: @escaping @Sendable (WindowKey, CGRect) -> Bool) { refusal.withLock { $0 = when } }
    /// 每次挪窗口前先调一下（检查挪的那一刻还原记录里写的是什么）
    func onMove(_ hook: @escaping @Sendable (WindowKey) -> Void) { moveHook.withLock { $0 = hook } }

    private var reachable: Bool { !blocked.withLock { $0 } }

    /// windowed：全屏窗口退出全屏后的平时位置
    func add(_ key: WindowKey, frame: CGRect, fullScreen: Bool = false, windowed: CGRect? = nil, minimized: Bool = false,
             hidden: Bool = false, shownFrom: TimeInterval = 0, info: WindowInfo? = nil) {
        state.withLock {
            $0[key] = Window(frame: frame, fullScreen: fullScreen, otherFrame: windowed, minimized: minimized, hidden: hidden,
                             shownFrom: shownFrom, info: info)
        }
    }
    /// App 重新显示藏起来的窗口（唤回）
    func unhide(_ key: WindowKey) { state.withLock { $0[key]?.hidden = false } }

    /// App 在问用户，问的是 key 这个窗口（挂着 sheet 的文档窗口，或单独的对话框）。answer 秒数到了就算答完：
    /// 不再问，接着做 then 里的事（App 退出、窗口关掉；什么都不做就是点了取消）
    struct Asking: Sendable {
        var key: WindowKey
        var answeredAt: TimeInterval?
        var then: (@Sendable () -> Void)?
    }
    func ask(_ key: WindowKey, answeredAfter delay: TimeInterval? = nil, then: (@Sendable () -> Void)? = nil) {
        let now = clock.withLock { $0 }?() ?? 0
        asking.withLock { $0 = Asking(key: key, answeredAt: delay.map { now + $0 }, then: then) }
    }

    /// 按关闭按钮时窗口的反应
    enum CloseReaction: Sendable {
        /// 问「要存储吗」（挂在它自己身上），过 after 秒答完：save 就关掉，否则是点了取消
        case asks(after: TimeInterval, save: Bool)
        /// 按了不关、也不问
        case stalls
        /// 像飞书、微信那样：点关闭只是把窗口藏起来
        case hides
    }
    func onClose(_ key: WindowKey, _ reaction: CloseReaction) { closeReactions.withLock { $0[key] = reaction } }

    /// 这个进程的窗口全关掉（App 退出）
    func closeAll(of pid: Int32) { state.withLock { $0 = $0.filter { $0.key.pid != pid } } }
    /// 窗口没了（用户在 Mac 上关掉、App 自己关掉）
    func vanish(_ key: WindowKey) { _ = state.withLock { $0.removeValue(forKey: key) } }
    /// 像飞书、微信点关闭那样：窗口藏起来，还在
    func hide(_ key: WindowKey) { state.withLock { $0[key]?.hidden = true } }
    func window(_ key: WindowKey) -> Window? { state.withLock { $0[key] } }
    /// 带着 bundle ID 的窗口都属于哪些进程（假 App 按它报 pids）
    func pids(bundleID: String) -> [Int32] {
        Array(Set(state.withLock { $0 }.compactMap { $0.value.info?.bundleID == bundleID ? $0.key.pid : nil })).sorted()
    }
    func setFrame(_ key: WindowKey, _ frame: CGRect) { state.withLock { $0[key]?.frame = frame } }

    private var mark: String {
        guard let ledger else { return "" }
        return FileManager.default.fileExists(atPath: ledger.path) ? " ✎" : " ∅"
    }

    func exists(_ window: WindowKey) async -> Bool { self.window(window) != nil }

    func isShown(_ window: WindowKey) async -> Bool {
        guard let w = self.window(window) else { return false }
        return shown(w)
    }

    private func shown(_ w: Window) -> Bool {
        !w.minimized && !w.hidden && (clock.withLock { $0 }?() ?? 0) >= w.shownFrom
    }

    private func info(_ key: WindowKey, _ w: Window) -> WindowInfo {
        w.info ?? WindowInfo(key: key, app: "App\(key.pid)", bundleID: nil, title: "")
    }

    func shownWindows(of pid: Int32) async -> [WindowInfo] {
        state.withLock { $0 }.filter { $0.key.pid == pid && shown($0.value) }
            .sorted { $0.key.id < $1.key.id }.map { info($0.key, $0.value) }
    }

    func askingWindow(of pid: Int32) async -> WindowInfo? {
        guard let a = asking.withLock({ $0 }), a.key.pid == pid else { return nil }
        if let at = a.answeredAt, (clock.withLock { $0 }?() ?? 0) >= at {
            asking.withLock { $0 = nil }
            a.then?()
            return nil
        }
        return window(a.key).map { info(a.key, $0) }
    }

    /// 全屏的按了没反应（和真的一样）
    func close(_ window: WindowKey) async -> Bool {
        guard reachable, let w = self.window(window) else { return false }
        journal.add("close \(window.id)\(w.fullScreen ? "（全屏，没反应）" : "")")
        guard !w.fullScreen else { return true }
        switch closeReactions.withLock({ $0[window] }) {
        case nil: vanish(window)
        case .asks(let after, let save): ask(window, answeredAfter: after) { if save { self.vanish(window) } }
        case .stalls: break
        case .hides: hide(window)
        }
        return true
    }

    func frames(of pid: Int32) async -> [WindowKey: CGRect] {
        state.withLock { $0 }.filter { $0.key.pid == pid && shown($0.value) }.mapValues(\.frame)
    }

    /// 关闭按钮在窗口左上角（和真的一样，大小随便给）
    func closeButton(_ window: WindowKey) async -> CGRect? {
        guard reachable, let w = self.window(window) else { return nil }
        return CGRect(x: w.frame.minX + 8, y: w.frame.minY + 8, width: 14, height: 14)
    }

    func look(_ window: WindowKey) async -> WindowLook? {
        guard reachable, let w = self.window(window) else { return nil }
        return WindowLook(frame: w.frame, fullScreen: w.fullScreen, minimized: w.minimized)
    }

    func move(_ window: WindowKey, to frame: CGRect) async -> CGRect? {
        guard reachable, !movesBlocked.withLock({ $0 }), self.window(window) != nil,
              refusal.withLock({ $0 })?(window, frame) != true else { return nil }
        moveHook.withLock { $0 }?(window)
        journal.add("move \(window.id) \(frame.short)\(mark)")
        if movesIgnored.withLock({ $0 }) { return self.window(window)?.frame }
        var got = frame
        if let min = minSizes.withLock({ $0[window] }) {
            got.size = CGSize(width: max(got.width, min.width), height: max(got.height, min.height))
        }
        setFrame(window, got)
        return got
    }

    /// 切全屏：和另一个样子对换（退出全屏变回平时的位置，进全屏变回整屏）
    func setFullScreen(_ window: WindowKey, _ on: Bool) async {
        guard reachable else { return }
        journal.add("fullscreen \(window.id) \(on ? "on" : "off")\(mark)")
        state.withLock {
            guard var w = $0[window], w.fullScreen != on else { return }
            (w.frame, w.otherFrame) = (w.otherFrame ?? w.frame, w.frame)
            w.fullScreen = on
            $0[window] = w
        }
    }

    func setMinimized(_ window: WindowKey, _ on: Bool) async {
        guard reachable else { return }
        journal.add("minimize \(window.id) \(on ? "on" : "off")\(mark)")
        state.withLock { $0[window]?.minimized = on }
    }

    func focus(_ window: WindowKey) async { journal.add("focus \(window.id)") }

    func zoom(_ window: WindowKey, steps: Int) async -> Bool {
        guard reachable, !zoomBlocked.withLock({ $0 }), self.window(window) != nil else { return false }
        journal.add("zoom \(window.id) \(steps > 0 ? "+" : "")\(steps)\(mark)")
        let grow = grows.withLock { $0 }
        state.withLock {
            $0[window]?.zoom += steps
            if grow { $0[window]?.frame.size.width += CGFloat(steps * 50) }
        }
        return true
    }

    func restoreZoom(_ window: WindowKey, appliedSteps: Int) async -> Bool {
        guard self.window(window)?.info?.bundleID == "com.googlecode.iterm2" else {
            return await zoom(window, steps: -appliedSteps)
        }
        guard reachable, !zoomBlocked.withLock({ $0 }) else { return false }
        journal.add("restore text \(window.id)\(mark)")
        state.withLock { $0[window]?.zoom = 0 }
        return true
    }

    /// 和真的一样只问窗口服务器：最小化、藏起来的不在屏上，不算
    func windows(in area: CGRect) async -> [WindowKey: CGRect] {
        state.withLock { all in
            all.filter { !$0.value.minimized && !$0.value.hidden && area.contains(CGPoint(x: $0.value.frame.midX, y: $0.value.frame.midY)) }
                .mapValues(\.frame)
        }
    }

    func snapshot() async -> [WindowKey: CGRect] {
        journal.add("snapshot")
        return state.withLock { $0.mapValues(\.frame) }
    }

    func restore(_ snapshot: [WindowKey: CGRect], except: Set<WindowKey>) async {
        journal.add("restore" + except.map { " except \($0.id)" }.sorted().joined())
        guard !movesIgnored.withLock({ $0 }) else { return }
        for (key, frame) in snapshot where !except.contains(key) && self.window(key)?.frame != frame {
            setFrame(key, frame)
        }
    }
}

/// 假的屏幕排布：每块屏的原点。设主屏 = 把它挪到原点、别的跟着平移
@MainActor
final class FakeArrangement: DisplayArrangement {
    let journal: Journal
    /// 内建屏（#1）在原点；建出来的假屏在 displays 里，原点按 FakeDisplays 的排法
    var origins_: [DisplayID: CGPoint] = [1: .zero]
    weak var displays: FakeDisplays?
    var fails = false
    /// 设主屏、摆回去时系统的副作用（原主屏上的窗口跟着主屏走）
    var onChange: (() -> Void)?

    init(journal: Journal) { self.journal = journal }

    func origins() -> [DisplayID: CGPoint] {
        var all = origins_
        for id in displays.map({ Array($0.widths.keys) }) ?? [] where all[id] == nil {
            all[id] = displays?.bounds(id)?.origin
        }
        return all
    }

    func makeMain(_ id: DisplayID) async -> Bool {
        journal.add("main \(id)")
        guard !fails, let shift = origins()[id] else { return false }
        origins_ = origins().mapValues { CGPoint(x: $0.x - shift.x, y: $0.y - shift.y) }
        onChange?()
        return true
    }

    func restore(_ saved: [DisplayID: CGPoint]) async -> Bool {
        journal.add("arrange \(saved.keys.sorted().map { "#\($0)" }.joined(separator: ","))")
        guard !fails else { return false }
        let online = origins()
        for (id, origin) in saved where online[id] != nil { origins_[id] = origin }
        onChange?()
        return true
    }

    /// 此刻的主屏
    var main: DisplayID? { origins().first { $0.value == .zero }?.key }
}

/// 假 App：启动、唤回、新建窗口时按事先登记的样子开出窗口（可以晚一会儿才出现在屏上），退出时按登记的反应来
final class FakeApps: AppControl {
    /// 打开、新建窗口时开出来的窗口：编号、位置、多久后出现在屏上；全屏的给出退出全屏后的位置
    struct Spawn: Sendable {
        var id: UInt32
        var frame: CGRect
        var delay: TimeInterval = 0
        var fullScreen = false
        var windowed: CGRect?
        var title = ""
    }

    /// 用户怎么答对话框：过 after 秒答完，存储（App 接着退出）或取消
    enum Answer: Sendable {
        case save(after: TimeInterval)
        case cancel(after: TimeInterval)
    }

    enum Quit: Sendable {
        case exits
        /// 过这么久才退完（大型 App）
        case slow(after: TimeInterval)
        /// 问「要存储吗」：挂在这个编号的窗口上；dialog 为 true 时另弹一个这个编号的对话框窗口
        case asks(UInt32, dialog: Bool = false, answer: Answer)
        /// 一直不退
        case stalls
        /// 请求送不到（terminate() 交回 false）
        case refuses
    }

    let journal: Journal
    let windows: FakeWindows
    private let timeline: ManualTimeline
    private let running = Locked<[Int32: AppInfo]>([:])
    private let spawns = Locked<[String: Spawn]>([:])
    private let quits = Locked<[String: Quit]>([:])
    private let reshows = Locked<[String: UInt32]>([:])
    /// 到点就退出的进程（慢慢退完、启动后崩溃）
    private let exitsAt = Locked<[Int32: TimeInterval]>([:])
    private let crashes = Locked<[String: TimeInterval]>([:])
    private let nextPID = Locked<Int32>(500)
    private let launchFails = Locked(false)
    private let forceRefused = Locked(false)

    init(journal: Journal, windows: FakeWindows, timeline: ManualTimeline) {
        self.journal = journal
        self.windows = windows
        self.timeline = timeline
    }

    /// 登记一个在跑的 App，交回列表里的样子
    @discardableResult
    func run(_ app: AppInfo, pid: Int32, windows: [WindowInfo] = []) -> RunningApp {
        running.withLock { $0[pid] = app }
        return RunningApp(pid: pid, app: app, windows: windows)
    }
    /// 打开、新建窗口时开出这个窗口；不登记的 App 菜单里没有「新建窗口」
    func willSpawn(_ app: AppInfo, _ spawn: Spawn) { spawns.withLock { $0[app.bundleID] = spawn } }
    func onQuit(_ app: AppInfo, _ quit: Quit) { quits.withLock { $0[app.bundleID] = quit } }
    /// 唤回时重新显示这个编号的窗口（原来关成了隐藏），不开新的
    func willReshow(_ app: AppInfo, id: UInt32) { reshows.withLock { $0[app.bundleID] = id } }
    /// 打不开（启动失败）
    func failLaunches() { launchFails.withLock { $0 = true } }
    /// 强制退出的请求送不到
    func refuseForceQuit() { forceRefused.withLock { $0 = true } }
    /// 启动 after 秒后自己退了（崩溃），一个窗口都没开出来
    func willCrash(_ app: AppInfo, after: TimeInterval) { crashes.withLock { $0[app.bundleID] = after } }

    private func spawn(for app: AppInfo, pid: Int32) {
        guard let s = spawns.withLock({ $0[app.bundleID] }) else { return }
        let key = WindowKey(pid: pid, id: s.id)
        windows.add(key, frame: s.frame, fullScreen: s.fullScreen, windowed: s.windowed, shownFrom: timeline.now + s.delay,
                    info: WindowInfo(key: key, app: app.name, bundleID: app.bundleID, title: s.title))
    }

    func pid(of app: AppInfo) async -> Int32? { running.withLock { $0.first { $0.value.bundleID == app.bundleID }?.key } }

    /// 登记过在跑的，加上窗口带着这个 bundle ID 的进程
    func pids(bundleID: String) async -> [Int32] {
        let registered = running.withLock { $0.filter { $0.value.bundleID == bundleID }.map(\.key) }
        return Array(Set(registered + windows.pids(bundleID: bundleID))).sorted()
    }

    func open(_ app: AppInfo) async -> Int32? {
        journal.add("open \(app.bundleID)")
        guard !launchFails.withLock({ $0 }) else { return nil }
        if let pid = await pid(of: app) {
            if let id = reshows.withLock({ $0[app.bundleID] }) { windows.unhide(WindowKey(pid: pid, id: id)) } else { spawn(for: app, pid: pid) }
            return pid
        }
        let pid = nextPID.withLock { $0 += 1; return $0 }
        run(app, pid: pid)
        if let after = crashes.withLock({ $0[app.bundleID] }) {
            exitsAt.withLock { $0[pid] = timeline.now + after }
        } else {
            spawn(for: app, pid: pid)
        }
        return pid
    }

    func newWindow(pid: Int32) async -> Bool {
        journal.add("newwin \(pid)")
        guard let app = running.withLock({ $0[pid] }), spawns.withLock({ $0[app.bundleID] }) != nil else { return false }
        spawn(for: app, pid: pid)
        return true
    }

    func quit(pid: Int32) async -> Bool {
        journal.add("quit \(pid)")
        guard let app = running.withLock({ $0[pid] }) else { return true }
        switch quits.withLock({ $0[app.bundleID] }) ?? .exits {
        case .exits: exit(pid)
        case .slow(let after): exitsAt.withLock { $0[pid] = timeline.now + after }
        case .asks(let id, let dialog, let answer):
            let key = WindowKey(pid: pid, id: id)
            if dialog {
                windows.add(key, frame: CGRect(x: 546, y: 380, width: 420, height: 160),
                            info: WindowInfo(key: key, app: app.name, bundleID: app.bundleID, title: ""))
            }
            switch answer {
            case .save(let after): windows.ask(key, answeredAfter: after) { self.exit(pid) }
            case .cancel(let after): windows.ask(key, answeredAfter: after) { if dialog { self.windows.vanish(key) } }
            }
        case .stalls: break
        case .refuses: return false
        }
        return true
    }

    func forceQuit(pid: Int32) async -> Bool {
        journal.add("force \(pid)")
        guard !forceRefused.withLock({ $0 }) else { return false }
        exit(pid)
        return true
    }

    func isRunning(pid: Int32) async -> Bool {
        if let at = exitsAt.withLock({ $0[pid] }), timeline.now >= at { exit(pid) }
        return running.withLock { $0[pid] } != nil
    }

    private func exit(_ pid: Int32) {
        exitsAt.withLock { $0[pid] = nil }
        guard running.withLock({ $0.removeValue(forKey: pid) }) != nil else { return }
        windows.closeAll(of: pid)
    }
}

/// 不真等的时钟：sleep 直接把时间往前拨
final class ManualTimeline: Timeline {
    private let clock = Locked<TimeInterval>(1000)
    var now: TimeInterval { clock.withLock { $0 } }
    func advance(_ seconds: TimeInterval) { clock.withLock { $0 += seconds } }
    func sleep(_ seconds: TimeInterval) async {
        advance(seconds)
        await Task.yield()
    }
}
