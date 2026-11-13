// 手机屏的调度中枢：什么时候加屏、撤屏，窗口怎么放上来、放回去，横竖怎么切，字号怎么改。
// 所有动作排成一队依次做（加屏要等上线、搬窗口要核对重试，中间不能被别的动作插进来）。
// 隔离：只动手机屏和放上来的那一个窗口；加屏、撤屏被系统挪动的其它窗口放回原处；
// 每一处改动先记账再动手，还原成功才销账（崩溃后下次启动 recover() 按账还原）
import CoreGraphics
import Foundation

@MainActor
public final class PhoneDesk {
    public struct State: Equatable, Sendable {
        public enum Screen: Equatable, Sendable {
            case off
            case preparing
            case ready(DisplayID)
            /// 加屏失败（详情在日志里）
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
        /// 要让用户知道的短提示（窗口已关闭……），下一个动作开始时清掉
        public var notice: String?

        public init() {}

        public var display: DisplayID? {
            if case .ready(let id) = screen { id } else { nil }
        }
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
    /// 窗口挪好后等这么久再发 ⌘+，App 才认到新的窗口大小
    static let zoomDelay: TimeInterval = 0.3

    public private(set) var state = State() {
        didSet { if state != oldValue { onChange?(state) } }
    }
    public var onChange: ((State) -> Void)?
    /// 即将加屏、撤屏：会话层据此暂缓断开判定（屏幕组合一变，UU 的信号会抖一下）
    public var onTopologyChange: (() -> Void)?
    /// 设置里的默认字号级数
    public var defaultZoom = 2

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
    private var verifying = false

    public init(displays: any PhoneDisplays, windows: any WindowControl, timeline: any Timeline = SystemTimeline(),
                paths: SnugPaths) {
        self.displays = displays
        self.windows = windows
        self.timeline = timeline
        ledger = RestoreRecord(url: paths.phoneRecord)
        zoomFile = JSONFile(url: paths.zoomBook)
        zoomBook = zoomFile.loadOrQuarantine() ?? ZoomBook()
    }

    // MARK: 意图

    /// 要不要手机屏（会话、设置、权限合起来的结论）。变了才动
    public func setWanted(_ on: Bool) {
        guard on != wanted else { return }
        wanted = on
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

    /// 定期调用：手机屏上的窗口被关掉了，就回到窗口列表
    public func verifyPlacement() {
        guard placement != nil, state.work == nil, !verifying, windows.canControl else { return }
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

    /// 有辅助功能权限后调用：上次 Snug 没来得及放回去的窗口，按记录放回去
    public func recover() {
        guard placement == nil, windows.canControl, let record = ledger.pending() else { return }
        lane.run { await self.recover(record) }
    }

    /// 退出前：放回窗口、撤掉手机屏，做完才返回
    public func shutdown() async {
        wanted = false
        await lane.run { await self.reconcile() }.value
    }

    /// 等排着的动作都做完（测试用）
    public func idle() async {
        await pendingRecheck?.value
        await lane.drain()
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
            await windows.restore(before, except: placement?.window.key)
            state.screen = .ready(id)
            Log.info("手机屏 #\(id) 已就绪（\(spec.width)x\(spec.height)）")
        } catch {
            state.screen = .failed
            Log.error("加手机屏失败：\(error)")
        }
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
        let before = await windows.snapshot()
        onTopologyChange?()
        await displays.retire(id)
        display = nil
        await windows.restore(before, except: placement?.window.key)
        Log.info("已撤掉手机屏 #\(id)")
    }

    private func flipOrientation() async {
        state.orientation = state.orientation.flipped
        guard display != nil else { return }
        // 先撤旧屏再建新屏：两块手机屏同时在时切好的 2 倍，旧屏一撤、屏幕组合一变，系统会把新屏退回 1 倍（实测）
        await retireDisplay()
        await addScreen()
        guard let p = placement else { return }
        guard let id = display?.id, let area = displays.windowArea(id) else {
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
        guard let p = placement, let area = displays.windowArea(id),
              let frame = await windows.frame(of: p.window.key), !frame.matches(area) else { return }
        Log.info("守护：\(p.window.label) 变成了 \(frame.short)，重新铺满")
        await windows.move(p.window.key, to: area)
    }

    // MARK: 放窗口

    private func place(_ window: WindowInfo) async {
        guard let id = display?.id, let area = displays.windowArea(id) else { return }
        if placement?.window.key == window.key {
            state.listVisible = false
            await windows.focus(window.key)
            return
        }
        if let p = placement { await returnToOriginal(p) }

        let wasFullScreen = await windows.isFullScreen(window.key)
        if wasFullScreen { await windows.setFullScreen(window.key, false) }
        guard let original = await windows.frame(of: window.key) else {
            Log.warn("读不到 \(window.label) 的位置（多半已经关了），不放")
            state.notice = "窗口已关闭"
            return
        }
        let next = Placement(window: window, original: original, wasFullScreen: wasFullScreen, zoom: 0)
        do {
            try ledger.record(next.record)
        } catch {
            Log.error("还原记录写不进去，不放 \(window.label)：\(error)")
            if wasFullScreen { await windows.setFullScreen(window.key, true) }
            state.notice = "无法写入还原记录"
            return
        }
        placement = next
        let got = await windows.move(window.key, to: area)
        await windows.focus(window.key)
        state.listVisible = false
        let filled = got.map { $0.matches(area) } ?? false
        Log.info("\(window.label) 放上手机屏：原位 \(original.short)\(wasFullScreen ? "（原来全屏）" : "")，"
                 + "\(filled ? "已铺满" : "没铺满，实际 \(got?.short ?? "?")")")

        let steps = zoomBook.steps(for: window.bundleID, default: defaultZoom)
        guard steps != 0 else { return }
        await timeline.sleep(Self.zoomDelay)
        await changeZoom(by: steps)
    }

    /// 放回原位：先缩回字号（窗口还在手机屏上、还是它 App 的当前窗口），再挪回去，原来全屏的恢复全屏
    private func returnToOriginal(_ p: Placement) async {
        if p.zoom != 0 { await windows.zoom(p.window.key, steps: -p.zoom) }
        let got = await windows.move(p.window.key, to: p.original)
        if got != nil, p.wasFullScreen {
            await timeline.sleep(0.3)
            await windows.setFullScreen(p.window.key, true)
        }
        placement = nil
        state.listVisible = true
        if got == nil, !windows.canControl {
            // 没有权限时看不到窗口，不是窗口关了：记录留着，有权限后 recover() 再放回
            Log.warn("没有辅助功能权限，\(p.window.label) 没能放回，留待有权限后放回")
            return
        }
        settleRecord()
        switch got {
        case nil: Log.info("\(p.window.label) 已经关了，不用放回")
        case let f? where f.matches(p.original):
            Log.info("\(p.window.label) 已放回原位\(p.wasFullScreen ? "并恢复全屏" : "")\(p.zoom != 0 ? "，字号缩回 \(p.zoom) 级" : "")")
        case let f?: Log.warn("\(p.window.label) 放回没对上：目标 \(p.original.short)，实际 \(f.short)")
        }
    }

    /// 先记账再发按键。返回是否真的改了
    @discardableResult
    private func changeZoom(by delta: Int) async -> Bool {
        guard var p = placement else { return false }
        let target = (p.zoom + delta).clamped(to: ZoomBook.range)
        guard target != p.zoom else { return false }
        var record = p.record
        record.zoom = target
        do {
            try ledger.record(record)
        } catch {
            Log.error("还原记录写不进去，不改字号：\(error)")
            state.notice = "无法写入还原记录"
            return false
        }
        guard await windows.zoom(p.window.key, steps: target - p.zoom) else {
            Log.warn("\(p.window.label) 不在了，字号没改")
            return false
        }
        p.zoom = target
        placement = p
        Log.info("\(p.window.label) 字号比原来 \(target > 0 ? "+" : "")\(target) 级")
        return true
    }

    private func recover(_ record: PhoneRecord) async {
        guard await windows.exists(record.window) else {
            Log.info("上次放在手机屏上的 \(record.label) 已经不在了（App 退出或窗口关了），还原记录作废")
            settleRecord()
            return
        }
        Log.info("上次 Snug 没来得及把 \(record.label) 放回去，现在放回 \(record.original.short)")
        if record.zoom != 0 { await windows.zoom(record.window, steps: -record.zoom) }
        await windows.move(record.window, to: record.original)
        if record.wasFullScreen { await windows.setFullScreen(record.window, true) }
        settleRecord()
    }

    // MARK: 小工具

    private func begin(_ work: Work) {
        state.notice = nil
        state.work = work
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
    let original: CGRect
    let wasFullScreen: Bool
    var zoom: Int

    var record: PhoneRecord {
        PhoneRecord(window: window.key, label: window.label, original: original, wasFullScreen: wasFullScreen, zoom: zoom)
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

extension CGRect {
    /// 日志里用：(x,y 宽x高)
    var short: String { "(\(Int(minX)),\(Int(minY)) \(Int(width))x\(Int(height)))" }
}
