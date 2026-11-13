// 手机屏的调度中枢：什么时候加屏、撤屏，窗口怎么放上来、放回去，横竖怎么切，字号怎么改。
// 所有动作排成一队依次做（加屏要等上线、搬窗口要核对重试，中间不能被别的动作插进来）。
// 隔离：只动手机屏和放上来的那一个窗口；加屏、撤屏被系统挪动的其它窗口放回原处；
// 每一处改动先记账再动手，还原成功、或窗口确实没了才销账（崩溃后下次启动 recover() 按账还原）
import CoreGraphics
import Foundation

@MainActor
public final class PhoneDesk {
    public struct State: Equatable, Sendable {
        public enum Screen: Equatable, Sendable {
            case off
            case preparing
            case ready(DisplayID)
            /// 加屏失败（详情在日志里），稍后自动重试
            case failed
        }

        public var screen = Screen.off
        public var orientation = Orientation.portrait
        /// 手机屏上的窗口
        public var placed: Placed?
        /// 手机屏上显示窗口列表。没放窗口时总是显示
        public var listVisible = true
        /// 正在做的事，做完回到 nil
        public var work: Work?
        /// 要让用户知道的事，下一个动作开始时清掉
        public var notice: Notice?

        public init() {}

        public var display: DisplayID? {
            if case .ready(let id) = screen { id } else { nil }
        }
    }

    /// 要让用户知道的事。措辞归界面层
    public enum Notice: Equatable, Sendable {
        /// 要放的窗口已经关了
        case windowGone
        /// 窗口还在，但读不到、挪不动（App 没响应，或没有辅助功能权限）
        case windowUnresponsive
        /// 还原记录写不进去，不敢动窗口
        case recordUnwritable
        /// 手机屏还没好（刚切完横竖、屏幕组合还在变）
        case screenNotReady
        /// 横竖切换没成，退回了原来的方向
        case rotateFailed
    }

    public struct Placed: Equatable, Sendable {
        public let window: WindowInfo
        /// 比原来放大了几级
        public var zoom: Int
        public var zoomable: Bool { ZoomBook.isZoomable(window.bundleID) }

        public init(window: WindowInfo, zoom: Int) {
            self.window = window
            self.zoom = zoom
        }
    }

    public enum Work: Equatable, Sendable {
        case placing(WindowKey)
        case puttingBack
        case rotating
        case zooming
    }

    /// 屏幕配置一变，过这么久再检查一次（等系统折腾完）
    public static let recheckDelay: TimeInterval = 1.5
    /// 窗口挪好、字号改完后等这么久再动下一步：App 要一点时间认到新的大小
    static let settleDelay: TimeInterval = 0.3
    /// 加屏失败后隔多久重试；这几次都不成就不再试，直到不要了再要
    static let retryDelays: [TimeInterval] = [5, 15, 30]

    public private(set) var state = State() {
        didSet { if state != oldValue { onChange?(state) } }
    }
    public var onChange: ((State) -> Void)?
    /// 即将加屏、撤屏：会话层据此暂缓断开判定（屏幕组合一变，UU 的信号会抖一下）
    public var onTopologyChange: (() -> Void)?
    /// 设置里的默认字号级数
    public private(set) var defaultZoom: Int

    private let displays: any PhoneDisplays
    private let windows: any WindowControl
    private let timeline: any Timeline
    private let ledger: RestoreRecord<PhoneRecord>
    private let zoomFile: JSONFile<ZoomBook>
    private var zoomBook: ZoomBook
    private let lane = SerialLane()

    private var wanted = false
    private var display: (id: DisplayID, bornAt: TimeInterval)?
    private var placement: Placement? {
        didSet { state.placed = placement.map { Placed(window: $0.window, zoom: $0.zoom) } }
    }
    private var recheckGeneration = 0
    private var pendingRecheck: Task<Void, Never>?
    private var failures = 0
    private var pendingRetry: Task<Void, Never>?
    private var verifying = false

    public init(displays: any PhoneDisplays, windows: any WindowControl, timeline: any Timeline = SystemTimeline(),
                paths: SnugPaths, defaultZoom: Int = 2) {
        self.displays = displays
        self.windows = windows
        self.timeline = timeline
        self.defaultZoom = defaultZoom
        ledger = RestoreRecord(url: paths.phoneRecord)
        zoomFile = JSONFile(url: paths.zoomBook)
        zoomBook = zoomFile.loadOrQuarantine() ?? ZoomBook()
    }

    // MARK: 意图

    /// 要不要手机屏（会话、设置、权限合起来的结论）。变了才动
    public func setWanted(_ on: Bool) {
        guard on != wanted else { return }
        wanted = on
        if !on { cancelRetry() }
        lane.run { await self.reconcile() }
    }

    /// 把这个窗口放上手机屏（原来那个先放回原位）
    public func pull(_ window: WindowInfo) {
        begin(.placing(window.key))
        lane.run {
            await self.place(window)
            self.state.work = nil
        }
    }

    /// 底部小横条：回到窗口列表
    public func showList() {
        state.notice = nil
        state.listVisible = true
    }

    /// 列表里点手机屏上现在那个窗口：回到它
    public func returnToPlaced() {
        guard let p = placement else { return }
        state.notice = nil
        state.listVisible = false
        lane.run { await self.windows.focus(p.window.key) }
    }

    /// 把手机屏上的窗口放回原位
    public func putBack() {
        guard placement != nil else { return }
        begin(.puttingBack)
        lane.run {
            if let p = self.placement { await self.returnToOriginal(p) }
            self.state.work = nil
        }
    }

    /// 横过来 / 竖回去
    public func rotate() {
        begin(.rotating)
        lane.run {
            await self.flipOrientation()
            self.state.work = nil
        }
    }

    /// 字大 / 字小一级，并记到这个 App 名下
    public func zoom(by delta: Int) {
        guard state.placed?.zoomable == true else { return }
        begin(.zooming)
        lane.run {
            if await self.changeZoom(by: delta), let p = self.placement, let bundle = p.window.bundleID {
                self.zoomBook.remember(p.zoom, for: bundle)
                self.saveZoomBook()
            }
            self.state.work = nil
        }
    }

    /// 设置里改了默认级数：以它为准，各 App 记住的级数一起清掉（不然改了看起来不起作用）
    public func setDefaultZoom(_ steps: Int) {
        defaultZoom = steps
        guard !zoomBook.remembered.isEmpty else { return }
        zoomBook.forgetAll()
        saveZoomBook()
    }

    /// 屏幕配置变了（插拔外接屏、系统改模式）：过一会儿检查手机屏还是不是 2 倍、窗口还铺不铺满
    public func displaysChanged() {
        guard display != nil else { return }
        recheckGeneration += 1
        let generation = recheckGeneration
        pendingRecheck = Task {
            await timeline.sleep(Self.recheckDelay)
            guard generation == recheckGeneration else { return }
            lane.run { await self.recheck() }
        }
    }

    /// 定期调用：手机屏上的窗口被关掉了，就回到窗口列表。只认窗口服务器的结论：App 一时没响应不算关了
    public func verifyPlacement() {
        guard placement != nil, state.work == nil, !verifying else { return }
        verifying = true
        lane.run {
            defer { self.verifying = false }
            guard let p = self.placement, await !self.windows.exists(p.window.key) else { return }
            Log.info("手机屏上的 \(p.window.label) 已经关了，回到窗口列表")
            self.placement = nil
            self.state.listVisible = true
            self.settleRecord()
        }
    }

    /// 有辅助功能权限后调用：上次 Snug 没来得及放回去的窗口，按记录放回去。记录在队里轮到时才读，不会拿旧的放两遍
    public func recover() {
        lane.run {
            guard self.placement == nil, let record = self.ledger.pending() else { return }
            guard await self.windows.exists(record.window) else {
                Log.info("上次放在手机屏上的 \(record.label) 已经不在了（App 退出或窗口关了），还原记录作废")
                self.settleRecord()
                return
            }
            Log.info("上次 Snug 没来得及把 \(record.label) 放回去，现在放回 \(record.original.short)")
            await self.putBack(record)
        }
    }

    /// 退出前：放回窗口、撤掉手机屏，做完才返回
    public func shutdown() async {
        wanted = false
        cancelRetry()
        await lane.run { await self.reconcile() }.value
    }

    /// 等排着的动作都做完，包括还没到点的重试（测试用）
    public func idle() async {
        var retry: Task<Void, Never>?
        repeat {
            retry = pendingRetry
            await pendingRecheck?.value
            await retry?.value
            await lane.drain()
        } while pendingRetry != retry
    }

    // MARK: 加屏、撤屏

    private func reconcile() async {
        if wanted, display == nil {
            await addScreen()
        } else if !wanted, state.screen != .off {
            await removeScreen()
        }
    }

    private func addScreen() async {
        let spec = PhoneScreenSpec(state.orientation)
        state.screen = .preparing
        let before = await windows.snapshot()
        onTopologyChange?()
        do {
            let id = try await displays.create(spec)
            display = (id, timeline.now)
            failures = 0
            await windows.restore(before, except: placement?.window.key)
            state.screen = .ready(id)
            Log.info("手机屏 #\(id) 已就绪（\(spec.width)x\(spec.height)）")
        } catch {
            state.screen = .failed
            Log.error("加手机屏失败：\(error)")
            scheduleRetry()
        }
    }

    /// 加屏失败后过一会儿再试：手机上没有任何入口能重来，不重试就要等这次远程结束
    private func scheduleRetry() {
        pendingRetry?.cancel()
        pendingRetry = nil
        guard failures < Self.retryDelays.count else {
            Log.error("加手机屏连续失败 \(failures + 1) 次，这次远程不再重试")
            return
        }
        let delay = Self.retryDelays[failures]
        failures += 1
        Log.info("\(Int(delay)) 秒后重试加手机屏（第 \(failures) 次重试）")
        pendingRetry = Task {
            await timeline.sleep(delay)
            guard !Task.isCancelled else { return }
            await lane.run { await self.reconcile() }.value
        }
    }

    private func cancelRetry() {
        pendingRetry?.cancel()
        pendingRetry = nil
        failures = 0
    }

    private func removeScreen() async {
        if let p = placement { await returnToOriginal(p) }
        await retireDisplay()
        state.screen = .off
        state.orientation = .portrait
        state.listVisible = true
    }

    private func retireDisplay() async {
        guard let (id, bornAt) = display else { return }
        let age = timeline.now - bornAt
        if age < PhoneScreenSpec.minimumLifetime { await timeline.sleep(PhoneScreenSpec.minimumLifetime - age) }
        let gone = displays.bounds(id)
        let before = await windows.snapshot()
        onTopologyChange?()
        await displays.retire(id)
        display = nil
        // 原本就在手机屏上的窗口（手机上新开的）交给系统安置：那块屏已经没了，放回原处只会落到屏幕外
        let elsewhere = gone.map { screen in before.filter { !screen.contains(CGPoint(x: $0.value.midX, y: $0.value.midY)) } }
        await windows.restore(elsewhere ?? before, except: placement?.window.key)
        Log.info("已撤掉手机屏 #\(id)")
    }

    private func flipOrientation() async {
        let from = state.orientation
        state.orientation = from.flipped
        guard display != nil else { return }
        // 先撤旧屏再建新屏：两块手机屏同时在时切好的 2 倍，旧屏一撤、屏幕组合一变，系统会把新屏退回 1 倍（实测）
        await retireDisplay()
        await addScreen()
        if display == nil {
            // 新方向建不出来：退回原来的方向，别让手机屏就此消失
            Log.warn("横竖切换：\(state.orientation) 的手机屏建不出来，退回 \(from)")
            state.orientation = from
            state.notice = .rotateFailed
            await addScreen()
        }
        guard let p = placement else { return }
        guard let area = readyArea(for: "横竖切换后放回 \(p.window.label)") else {
            await returnToOriginal(p)
            return
        }
        await windows.move(p.window.key, to: area)
        await windows.focus(p.window.key)
        state.listVisible = false
    }

    private func recheck() async {
        guard let id = display?.id else { return }
        if await !displays.ensureHiDPI(id, PhoneScreenSpec(state.orientation)) {
            Log.warn("守护：手机屏 #\(id) 切不回 2 倍")
        }
        await refill(because: "屏幕配置变了")
    }

    /// 窗口不再铺满手机屏就重新铺满（屏幕配置变了；终端类 App 调字号时会按行列数撑大窗口）
    private func refill(because reason: String) async {
        guard let id = display?.id, let p = placement, let area = displays.windowArea(id),
              let frame = await windows.look(p.window.key)?.frame, !frame.matches(area) else { return }
        Log.info("\(reason)，\(p.window.label) 变成了 \(frame.short)，重新铺满")
        await windows.move(p.window.key, to: area)
    }

    // MARK: 放窗口

    private func place(_ window: WindowInfo) async {
        guard let area = readyArea(for: "放 \(window.label)") else {
            state.notice = .screenNotReady
            return
        }
        if placement?.window.key == window.key {
            state.listVisible = false
            await windows.focus(window.key)
            return
        }
        if let p = placement { await returnToOriginal(p) }

        guard let look = await windows.look(window.key) else {
            let notice = await unreachable(window.key)
            Log.warn("读不到 \(window.label)（\(notice == .windowGone ? "已经关了" : "App 没响应或没有辅助功能权限")），不放")
            state.notice = notice
            return
        }
        // 先记账再动手。全屏的窗口这时读到的是全屏的位置，崩溃后按它放回再恢复全屏也对
        var next = Placement(window: window, original: look.frame, wasFullScreen: look.fullScreen,
                             wasMinimized: look.minimized, zoom: 0)
        guard write(next.record) else {
            state.notice = .recordUnwritable
            return
        }
        if look.minimized { await windows.setMinimized(window.key, false) }
        if look.fullScreen {
            await windows.setFullScreen(window.key, false)
            // 退出全屏后的位置才是它平时的位置：放回时回到这里再进全屏
            if let windowed = await windows.look(window.key)?.frame {
                next.original = windowed
                write(next.record)
            }
        }
        placement = next
        guard let got = await windows.move(window.key, to: area) else {
            let notice = await unreachable(window.key)
            Log.warn("\(window.label) 挪不上手机屏（\(notice == .windowGone ? "刚关了" : "App 没响应")），放回去")
            placement = nil
            await putBack(next.record)
            state.notice = notice
            return
        }
        await windows.focus(window.key)
        state.listVisible = false
        let was = look.fullScreen ? "（原来全屏）" : look.minimized ? "（原来最小化）" : ""
        Log.info("\(window.label) 放上手机屏：原位 \(next.original.short)\(was)，"
                 + "\(got.matches(area) ? "已铺满" : "没铺满，实际 \(got.short)")")

        let steps = zoomBook.steps(for: window.bundleID, default: defaultZoom)
        guard steps != 0 else { return }
        await timeline.sleep(Self.settleDelay)
        await changeZoom(by: steps)
    }

    private func returnToOriginal(_ p: Placement) async {
        await putBack(p.record)
        placement = nil
        state.listVisible = true
    }

    /// 按记录放回：缩回字号（窗口还在手机屏上、还是它 App 的当前窗口；缩完马上记账）→ 挪回原位 →
    /// 原来全屏的恢复全屏、原来最小化的再最小化。放回了、或窗口确实没了才销账；
    /// 窗口还在却挪不动（App 没响应、没有权限）就留着记录，下次启动按它再放
    private func putBack(_ record: PhoneRecord) async {
        var record = record
        let zoom = record.zoom
        if zoom != 0, await windows.zoom(record.window, steps: -zoom) {
            record.zoom = 0
            write(record)
        }
        guard let got = await windows.move(record.window, to: record.original) else {
            if await windows.exists(record.window) {
                Log.warn("\(record.label) 还在，但挪不动（App 没响应或没有辅助功能权限），还原记录留着，下次启动再放回")
            } else {
                Log.info("\(record.label) 已经关了，不用放回")
                settleRecord()
            }
            return
        }
        if record.wasFullScreen {
            await timeline.sleep(Self.settleDelay)
            await windows.setFullScreen(record.window, true)
        } else if record.wasMinimized {
            await windows.setMinimized(record.window, true)
        }
        settleRecord()
        if got.matches(record.original) {
            let restored = record.wasFullScreen ? "并恢复全屏" : record.wasMinimized ? "并最小化" : ""
            Log.info("\(record.label) 已放回原位\(restored)\(zoom != 0 ? "，字号缩回 \(zoom) 级" : "")")
        } else {
            Log.warn("\(record.label) 放回没对上：目标 \(record.original.short)，实际 \(got.short)")
        }
    }

    /// 先记账再发按键，改完核对窗口还铺不铺满。返回是否真的改了
    @discardableResult
    private func changeZoom(by delta: Int) async -> Bool {
        guard var p = placement else { return false }
        let target = (p.zoom + delta).clamped(to: ZoomBook.range)
        guard target != p.zoom else { return false }
        var record = p.record
        record.zoom = target
        guard write(record) else {
            state.notice = .recordUnwritable
            return false
        }
        guard await windows.zoom(p.window.key, steps: target - p.zoom) else {
            // 按键没发出去：记录改回原来的级数，不然还原时会多缩
            write(p.record)
            state.notice = await unreachable(p.window.key)
            Log.warn("\(p.window.label) 找不到了，字号没改")
            return false
        }
        p.zoom = target
        placement = p
        Log.info("\(p.window.label) 字号比原来 \(target > 0 ? "+" : "")\(target) 级")
        await timeline.sleep(Self.settleDelay)
        await refill(because: "字号改了")
        return true
    }

    // MARK: 小工具

    private func begin(_ work: Work) {
        state.notice = nil
        state.work = work
    }

    /// 手机屏的可放区域；没好时写明是哪一步没好
    private func readyArea(for what: String) -> CGRect? {
        guard let id = display?.id else {
            Log.warn("\(what)：没有手机屏（\(state.screen)）")
            return nil
        }
        guard let area = displays.windowArea(id) else {
            Log.warn("\(what)：读不到手机屏 #\(id) 的可放区域（屏幕组合可能还在变）")
            return nil
        }
        return area
    }

    /// 读不到、挪不动的窗口：是关了，还是 App 没响应
    private func unreachable(_ window: WindowKey) async -> Notice {
        await windows.exists(window) ? .windowUnresponsive : .windowGone
    }

    @discardableResult
    private func write(_ record: PhoneRecord) -> Bool {
        do {
            try ledger.record(record)
            return true
        } catch {
            Log.error("还原记录写不进去（\(record.label)）：\(error)")
            return false
        }
    }

    private func settleRecord() {
        do {
            try ledger.settle()
        } catch {
            // 删不掉的记录下次启动会再还原一次：窗口已经在原位，再挪一次也是原位
            Log.error("还原记录删不掉：\(error)")
        }
    }

    private func saveZoomBook() {
        do {
            try zoomFile.save(zoomBook)
        } catch {
            Log.error("记不住字号级数（zoom.json 写不进去）：\(error)")
        }
    }
}

/// 放在手机屏上的那个窗口，以及放回去要用的东西
private struct Placement {
    let window: WindowInfo
    var original: CGRect
    let wasFullScreen: Bool
    let wasMinimized: Bool
    var zoom: Int

    var record: PhoneRecord {
        PhoneRecord(window: window.key, label: window.label, original: original, wasFullScreen: wasFullScreen,
                    wasMinimized: wasMinimized, zoom: zoom)
    }
}

/// 一条队：动作按提交顺序一个做完再做下一个
@MainActor
final class SerialLane {
    private var tail: Task<Void, Never>?

    @discardableResult
    func run(_ operation: @escaping @MainActor @Sendable () async -> Void) -> Task<Void, Never> {
        let previous = tail
        let task = Task { @MainActor in
            await previous?.value
            await operation()
        }
        tail = task
        return task
    }

    func drain() async {
        while let current = tail {
            await current.value
            if tail == current { return }
        }
    }
}
