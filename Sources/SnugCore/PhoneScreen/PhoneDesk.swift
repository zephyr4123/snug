// 手机屏的调度中枢：什么时候加屏、撤屏，窗口怎么放上来、放回去，字号怎么改，手机屏用哪一档。
// 所有动作排成一队依次做（加屏要等上线、搬窗口要核对重试，中间不能被别的动作插进来）。
// 屏幕适配（ScreenFit）：手机屏的宽度跟着屏上显示的东西走，露着列表是基准宽度，放着窗口是那个窗口要的一档。
// 隔离：只动手机屏和放上来的那一个窗口；加屏、撤屏被系统挪动的其它窗口放回原处；
// 每一处改动先记账再动手，还原成功、或窗口确实没了才销账。没销的账（Snug 崩溃、App 卡住没放成）
// 在下次启动（recover()）、或下次放窗口之前按账还原，不会被新的记录盖掉
import CoreGraphics
import Foundation

@MainActor
public final class PhoneDesk {
    public struct State: Equatable, Sendable {
        public enum Screen: Equatable, Sendable {
            case off
            case preparing
            case ready(DisplayID)
            /// 加屏失败（详情在日志里）。按 retryDelays 自动重试，用完就停在这里，直到不要了再要
            case failed
        }

        public var screen = Screen.off
        /// 手机屏上的窗口
        public var placed: Placed?
        /// 手机屏上显示窗口列表。没放窗口时总是显示
        public var listVisible = true
        /// 正在做的事，做完回到 nil
        public var work: Work?
        /// 要让用户知道的事，下一个动作开始时、或这次远程结束时清掉
        public var notice: Notice?

        public init() {}

        public var display: DisplayID? {
            if case .ready(let id) = screen { id } else { nil }
        }
    }

    /// 要让用户知道的事，带上是哪个 App 的窗口。措辞归界面层
    public enum Notice: Equatable, Sendable {
        /// 要放的窗口已经关了
        case windowGone(app: String)
        /// 窗口还在，但读不到、挪不动（App 没响应，或没有辅助功能权限）
        case windowUnresponsive(app: String)
        /// 还原记录写不进去，不敢动窗口
        case recordUnwritable
        /// 手机屏还没好（屏幕组合还在变）
        case screenNotReady
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
        /// 正在把这个窗口放上来（换窗口时含放回原来那个），窗口挪好就转成 zooming
        case placing(WindowInfo)
        case puttingBack
        case zooming
    }

    /// 屏幕配置一变，过这么久再检查一次（等系统折腾完）
    static let recheckDelay: TimeInterval = 1.5
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
        didSet { state.placed = placement.map { Placed(window: $0.window, zoom: $0.record.zoom) } }
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
        begin(.placing(window))
        lane.run {
            await self.place(window)
            self.state.work = nil
        }
    }

    /// 底部小横条：回到窗口列表（马上露出来），手机屏换回基准宽度。
    /// 提示留着：列表收着时出的错（比如调字号没成），这时才看得到
    public func showList() {
        state.listVisible = true
        lane.run { await self.matchWidth() }
    }

    /// 列表左上角的返回键：回到手机屏上的窗口。换档要一会儿，期间和放窗口一样显示「正在打开」、列表点不了
    public func returnToPlaced() {
        guard let p = placement else { return }
        begin(.placing(p.window))
        lane.run {
            await self.reveal()
            self.state.work = nil
        }
    }

    /// 把手机屏上的窗口放回原位。放不回去（App 卡住）就留在手机屏上，提示一下，可以再点
    public func putBack() {
        guard placement != nil else { return }
        begin(.puttingBack)
        lane.run {
            if let p = self.placement, await !self.returnToOriginal(p) {
                self.state.notice = .windowUnresponsive(app: p.window.app)
            }
            await self.matchWidth()
            self.state.work = nil
        }
    }

    /// 字大 / 字小一级，并记到这个 App 名下。到了上下限什么都不做（界面上那个按钮已经点不了）
    public func zoom(by delta: Int) {
        guard let placed = state.placed, placed.zoomable,
              (placed.zoom + delta).clamped(to: ZoomBook.range) != placed.zoom else { return }
        begin(.zooming)
        lane.run {
            if await self.changeZoom(by: delta), let p = self.placement, let bundle = p.window.bundleID {
                self.zoomBook.remember(p.record.zoom, for: bundle)
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

    /// 屏幕配置变了（插拔外接屏、系统改模式、Snug 自己换档）：过一会儿检查手机屏还是不是该用的那一档、窗口还铺不铺满
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

    /// 定期调用：手机屏上的窗口被关掉了，就回到窗口列表。只认窗口服务器的结论：App 一时没响应不算关了。
    /// 窗口还在却不在屏上（被最小化、App 被隐藏、关成了隐藏），手机屏上只剩空桌面：也回到列表，
    /// 但它照旧算放着、还原记录留着，可以返回它、还原或换一个
    public func verifyPlacement() {
        guard placement != nil, state.work == nil, !verifying else { return }
        verifying = true
        lane.run {
            defer { self.verifying = false }
            guard let p = self.placement else { return }
            guard await self.windows.exists(p.window.key) else {
                Log.info("手机屏上的 \(p.window.label) 已经关了，回到窗口列表")
                self.placement = nil
                self.state.listVisible = true
                self.settleRecord()
                await self.matchWidth()
                return
            }
            if !self.state.listVisible, await !self.windows.isShown(p.window.key) {
                Log.info("手机屏上的 \(p.window.label) 不在屏上了（最小化、隐藏或关成了隐藏），回到窗口列表")
                self.state.listVisible = true
                await self.matchWidth()
            }
        }
    }

    /// 有辅助功能权限后调用：上次 Snug 没来得及放回去的窗口，按记录放回去。记录在队里轮到时才读，不会拿旧的放两遍
    public func recover() {
        lane.run { await self.putBackLeftover() }
    }

    /// 退出前：放回窗口、撤掉手机屏，做完才返回
    public func shutdown() async {
        wanted = false
        cancelRetry()
        await lane.run { await self.reconcile() }.value
    }

    /// 等排着的动作都做完，包括还没到点的重试（测试用：真实时钟下最长要等 30 秒的重试）
    func idle() async {
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
        state.screen = .preparing
        let before = await windows.snapshot()
        onTopologyChange?()
        do {
            let id = try await displays.create()
            display = (id, timeline.now)
            failures = 0
            await windows.restore(before, except: placement?.window.key)
            state.screen = .ready(id)
            Log.info("手机屏 #\(id) 已就绪（\(displays.width(id).map { "\($0) 宽" } ?? "不是 2 倍")）")
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
        // 屏要撤了，手机屏上不再算有窗口；放不回去的留着还原记录，下次放窗口或下次启动再放
        if let p = placement { await putBack(p.record) }
        placement = nil
        await retireDisplay()
        state.screen = .off
        state.listVisible = true
        // 这次远程的提示不带到下一次
        state.notice = nil
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

    private func recheck() async {
        if state.listVisible { await matchWidth() } else { await refill(because: "屏幕配置变了") }
    }

    /// 窗口没铺好就重新铺：手机屏不在它那一档（刚从列表回来、换档没成、系统改了模式），
    /// 或者窗口被挪动、撑大了（换档时系统会挪它；终端类 App 调字号时会按行列数撑大窗口）。
    /// 跟上次挪完的样子比，不跟可放区域比：比最宽一档还宽的窗口本来就铺不满，再挪也一样
    private func refill(because reason: String) async {
        guard let id = display?.id, var p = placement, let frame = await windows.look(p.window.key)?.frame else { return }
        let moved = p.settled.map { !frame.matches($0) } ?? true
        guard moved || displays.width(id) != p.width else { return }
        let what = moved ? "变成了 \(frame.short)" : "要的 \(p.width) 宽不是手机屏现在这一档"
        Log.info("\(reason)，\(p.window.label) \(what)，重新铺满")
        await fill(&p, on: id)
        placement = p
    }

    // MARK: 屏幕适配

    /// 手机屏该用哪一档：露着列表（或没放窗口）是基准宽度，放着窗口是它那一档
    private var wantedWidth: Int {
        guard let p = placement, !state.listVisible else { return ScreenFit.baseWidth }
        return p.width
    }

    /// 让手机屏跟上该用的那一档
    private func matchWidth() async {
        guard let id = display?.id else { return }
        await switchWidth(id, to: wantedWidth)
    }

    private func switchWidth(_ id: DisplayID, to width: Int) async {
        if displays.width(id) != width { await displays.setWidth(id, width) }
    }

    /// 手机屏换到窗口那一档，把窗口铺满。铺不满（App 限定了最小尺寸）就按它实际的大小换到装得下的一档再铺。
    /// 换档没成时屏还是原来那一档，算出来的还是这一档，不会一直往上换。返回最后挪到的位置；挪不动（窗口关了、App 没响应）返回 nil
    @discardableResult
    private func fill(_ p: inout Placement, on id: DisplayID) async -> CGRect? {
        await switchWidth(id, to: p.width)
        guard let area = displays.windowArea(id), let got = await windows.move(p.window.key, to: area) else { return nil }
        p.settled = got
        // 窗口落到了区域原点、只是尺寸被夹住，才是 App 限定了最小尺寸；没挪过去（App 不认挪动）就不按它的大小换档
        let placed = abs(got.minX - area.minX) < 2 && abs(got.minY - area.minY) < 2
        guard placed, let current = displays.width(id) else { return got }
        let width = ScreenFit.width(toFit: got.size, in: area.size, at: current)
        guard width > current, width != p.width else { return got }
        Log.info("\(p.window.label) 在 \(current) 宽的手机屏上铺不满（App 限定了最小尺寸，实际 \(got.short)），换到 \(width) 宽")
        p.width = width
        return await fill(&p, on: id)
    }

    /// 收起列表、露出手机屏上的窗口：先换到它那一档、重新铺满，再收列表、激活它。
    /// 换档时列表还盖着，手机上看不到窗口被挪来挪去
    private func reveal() async {
        guard let id = display?.id, let p = placement else { return }
        // 先换档：App 一时读不到时 refill 什么都不做，档位也得对；换档触发的复查会在 App 恢复后补铺
        await switchWidth(id, to: p.width)
        await refill(because: "回到窗口")
        state.listVisible = false
        await windows.focus(p.window.key)
    }

    // MARK: 放窗口

    private func place(_ window: WindowInfo) async {
        let started = timeline.now
        guard let id = readyDisplay(for: "放 \(window.label)") else {
            state.notice = .screenNotReady
            return
        }
        if placement?.window.key == window.key {
            await reveal()
            return
        }
        // 先确认要放的窗口够得着，再动手机屏上现在那个：点到刚关掉的卡片，不能先把现在的拆了、两头落空
        guard await reach(window) != nil else { return }
        // 原来那个、或上次没放回去的那个放不回去（App 卡住）就不放：两个窗口会叠在手机屏上，还原记录也只记得住一个
        if let p = placement, await !returnToOriginal(p) {
            Log.warn("\(p.window.label) 放不回去，先不换成 \(window.label)")
            state.notice = .windowUnresponsive(app: p.window.app)
            return
        }
        if let stuck = await putBackLeftover() {
            Log.warn("\(stuck.label) 还放不回去，先不放 \(window.label)")
            state.notice = .windowUnresponsive(app: stuck.app)
            return
        }
        // 放回别的窗口可能动到它（上次没放回去的就是它），重新读
        guard let look = await reach(window) else { return }
        // 先记账再动手。全屏的窗口这时读到的是全屏的位置，崩溃后按它放回再恢复全屏也对
        var next = Placement(window: window, record: PhoneRecord(
            window: window.key, app: window.app, label: window.label, original: look.frame,
            wasFullScreen: look.fullScreen, wasMinimized: look.minimized))
        guard write(next.record) else {
            state.notice = .recordUnwritable
            return
        }
        if look.minimized { await windows.setMinimized(window.key, false) }
        if look.fullScreen {
            await windows.setFullScreen(window.key, false)
            // 退出全屏后的位置才是它平时的位置：放回时回到这里再进全屏
            if let windowed = await windows.look(window.key)?.frame {
                next.record.original = windowed
                write(next.record)
            }
        }
        placement = next
        // 先按基准宽度铺，App 卡在自己的最小尺寸上时换档再铺；这时列表还盖着（「正在打开」）
        guard let got = await fill(&next, on: id) else {
            let notice = await unreachable(window)
            Log.warn("\(window.label) 挪不上手机屏（\(Self.reason(notice, gone: "刚关了"))），放回去")
            placement = nil
            await putBack(next.record)
            // 露着列表：手机屏可能停在铺的中途换过的那一档
            await matchWidth()
            state.notice = notice
            return
        }
        placement = next
        await windows.focus(window.key)
        state.listVisible = false
        let was = look.fullScreen ? "（原来全屏）" : look.minimized ? "（原来最小化）" : ""
        let took = String(format: "%.1f", timeline.now - started)
        let fill = Self.describeFill(got, in: displays.windowArea(id), width: displays.width(id) ?? next.width)
        Log.info("\(window.label) 放上手机屏（\(took)s）：原位 \(next.record.original.short)\(was)，\(fill)")

        let steps = zoomBook.steps(for: window.bundleID, default: defaultZoom)
        guard steps != 0 else { return }
        // 窗口已经在手机屏上了，剩下的只是调字号
        state.work = .zooming
        await timeline.sleep(Self.settleDelay)
        await changeZoom(by: steps)
    }

    /// 放回原位、回到窗口列表，返回放回去了没有。
    /// 没放回去时窗口还在手机屏上，照旧算放着（字号按实际缩回了多少算），还原记录也留着
    private func returnToOriginal(_ p: Placement) async -> Bool {
        if let left = await putBack(p.record) {
            var p = p
            p.record = left
            placement = p
            return false
        }
        placement = nil
        state.listVisible = true
        return true
    }

    /// 按记录放回：缩回字号（窗口还在手机屏上、还是它 App 的当前窗口；缩完马上记账）→ 挪回原位 →
    /// 原来全屏的恢复全屏、原来最小化的再最小化。放回了、或窗口确实没了才销账，返回 nil；
    /// 窗口还在却缩不回、挪不动（App 没响应、没有权限）就留着记录（下次放窗口或下次启动再放），返回留下的这条
    @discardableResult
    private func putBack(_ record: PhoneRecord) async -> PhoneRecord? {
        var record = record
        let zoom = record.zoom
        if zoom != 0 {
            // 缩不回就先不挪：挪回原位就销账了，多出来的字号再也没人缩
            guard await windows.zoom(record.window, steps: -zoom) else { return await stuckOrGone(record, "缩不回字号") }
            record.zoom = 0
            write(record)
        }
        guard let got = await windows.move(record.window, to: record.original) else {
            return await stuckOrGone(record, "挪不动")
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
        return nil
    }

    /// 上次没放回去的窗口（Snug 崩溃，或 App 卡住没放成）：按还原记录放回去。
    /// 放下一个窗口之前必须先做，不然新记录会把它的原位和字号永远盖掉。返回仍然放不回去的那条
    @discardableResult
    private func putBackLeftover() async -> PhoneRecord? {
        guard placement == nil, let record = ledger.pending() else { return nil }
        guard await windows.exists(record.window) else {
            Log.info("还原记录里的 \(record.label) 已经不在了（App 退出或窗口关了），记录作废")
            settleRecord()
            return nil
        }
        Log.info("\(record.label) 上次没放回去，现在放回 \(record.original.short)")
        return await putBack(record)
    }

    /// 放回时有一步做不了：窗口还在就留着记录、返回这条，确实没了就销账
    private func stuckOrGone(_ record: PhoneRecord, _ what: String) async -> PhoneRecord? {
        if await windows.exists(record.window) {
            Log.warn("\(record.label) 还在，但\(what)（App 没响应或没有辅助功能权限），还原记录留着，稍后再放回")
            return record
        }
        Log.info("\(record.label) 已经关了，不用放回")
        settleRecord()
        return nil
    }

    /// 先记账再发按键，改完核对窗口还铺不铺满。返回是否真的改了
    @discardableResult
    private func changeZoom(by delta: Int) async -> Bool {
        guard var p = placement else { return false }
        let before = p.record
        let target = (before.zoom + delta).clamped(to: ZoomBook.range)
        guard target != before.zoom else { return false }
        p.record.zoom = target
        guard write(p.record) else {
            state.notice = .recordUnwritable
            return false
        }
        guard await windows.zoom(p.window.key, steps: target - before.zoom) else {
            // 按键没发出去：记录改回原来的级数，不然还原时会多缩
            write(before)
            state.notice = await unreachable(p.window)
            Log.warn("\(p.window.label) 找不到了，字号没改")
            return false
        }
        placement = p
        Log.info("\(p.window.label) 字号比原来 \(target > 0 ? "+" : "")\(target) 级")
        await timeline.sleep(Self.settleDelay)
        // 在列表里调的字号：窗口被盖着，返回时 reveal 再补铺；这时铺会把屏换到窗口那一档
        if !state.listVisible { await refill(because: "字号改了") }
        return true
    }

    // MARK: 小工具

    private func begin(_ work: Work) {
        state.notice = nil
        state.work = work
    }

    /// 可以放窗口的手机屏；没好时写明是哪一步没好
    private func readyDisplay(for what: String) -> DisplayID? {
        guard let id = display?.id else {
            Log.warn("\(what)：没有手机屏（\(state.screen)）")
            return nil
        }
        guard displays.windowArea(id) != nil else {
            Log.warn("\(what)：读不到手机屏 #\(id) 的可放区域（屏幕组合可能还在变）")
            return nil
        }
        return id
    }

    /// 铺满了没有、用的哪一档。没铺满是 App 要的比最宽一档还宽，或者换档没成（见前面的日志）
    private static func describeFill(_ got: CGRect, in area: CGRect?, width: Int) -> String {
        let screen = width == ScreenFit.baseWidth ? "" : "（手机屏 \(width) 宽）"
        if let area, got.matches(area) { return "已铺满\(screen)" }
        return "没铺满\(screen)，实际 \(got.short)"
    }

    /// 读要放的窗口；读不到就提示是关了还是 App 没响应
    private func reach(_ window: WindowInfo) async -> WindowLook? {
        if let look = await windows.look(window.key) { return look }
        let notice = await unreachable(window)
        Log.warn("读不到 \(window.label)（\(Self.reason(notice, gone: "已经关了"))），不放")
        state.notice = notice
        return nil
    }

    /// 读不到、挪不动的窗口：是关了，还是 App 没响应
    private func unreachable(_ window: WindowInfo) async -> Notice {
        await windows.exists(window.key) ? .windowUnresponsive(app: window.app) : .windowGone(app: window.app)
    }

    /// 日志里的原因
    private static func reason(_ notice: Notice, gone: String) -> String {
        if case .windowGone = notice { gone } else { "App 没响应或没有辅助功能权限" }
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

/// 放在手机屏上的那个窗口：它的还原记录（写进盘里的就是这一份，不另抄字段）、它要的那一档和上次挪完的样子
private struct Placement {
    let window: WindowInfo
    var record: PhoneRecord
    /// 手机屏用哪一档（ScreenFit）：先按基准宽度，铺不满时换成装得下它的一档
    var width = ScreenFit.baseWidth
    /// 上次挪完的样子：比最宽一档还宽的窗口铺不满，以它为准判断窗口有没有被再挪动
    var settled: CGRect?
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
