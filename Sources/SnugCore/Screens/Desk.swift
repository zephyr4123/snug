// 一块屏上的事，每块屏一个：放着哪个窗口、App 资源库露没露、正在做什么、有什么提示，都是这块屏自己的。
// 窗口怎么放上来、放回去，字号怎么改，屏用哪一档（ScreenFit）：手机、平板屏上窗口铺满、宽度跟着屏上显示的东西走，
// 露着列表是基准宽度，放着窗口是那个窗口要的一档；电脑屏上窗口只挪过来居中，不铺满、不调字号、不换档，可以挪过来好几个。
// 不建屏、不撤屏；换档经 ScreenSet。
// 隔离：只动放上来的窗口。每一处改动先记账再动手，还原成功才销账（触屏一块屏一份账，电脑屏挪过来的窗口一个一份）；
// 没销的账（Snug 崩溃、App 卡住没放成）在下次启动（DeskSet.recover）、或下次在这块屏上放窗口之前按账还原，
// 不会被新的记录盖掉。窗口在 Snug 之外没了，账转成留下的账（LeftBehind），它带着屏上的大小回来时再还。
// 方法都在 DeskSet 的队里调用，一个做完再做下一个
import CoreGraphics
import Foundation

@MainActor
public final class Desk {
    public struct State: Equatable, Sendable {
        public var screen = ScreenSet.State.off
        /// 这块屏的行为（ScreenPlan 按型号的类别给）：界面按它决定有没有面板、手势翻不翻译
        public var behavior = ScreenBehavior.touchScreen
        /// 面板和窗口使用实际建好的屏的底栏样式。换型号失败时仍按上一次生效的尺寸摆放。
        public var homeBarStyle = ScreenFit.HomeBarStyle.phone
        /// 屏上的窗口
        public var placed: Placed?
        /// 电脑屏上 Snug 挪过来、还记着原处的窗口：资源库里可以一键还原
        public var brought: Set<WindowKey> = []
        /// 屏上露着 App 资源库。没放窗口时总是露着
        public var listVisible = true
        /// 正在做的事，做完回到 nil
        public var work: Work?
        /// 要让用户知道的事，下一个动作开始时、或这次远程结束时清掉
        public var notice: Notice?
        /// 屏上那个窗口的关闭按钮（铺好后读的）。在手机上点它不直接关，先放回原位再关（见 DeskSet.closePlaced）。
        /// 在问用户的窗口（挂着「要存储吗」）不给：那时按钮是灰的，点它是想答对话框
        public var closeButton: CloseButton?

        public init() {}

        public var display: DisplayID? { screen.display }
    }

    /// 要让用户知道的事，带上是哪个 App 的窗口。措辞归界面层
    public enum Notice: Equatable, Sendable {
        /// 要放的窗口已经关了
        case windowGone(app: String)
        /// 窗口还在，但读不到、挪不动、关不掉（App 没响应，或没有辅助功能权限）；或者请它退出、强制退出的请求没送到
        case windowUnresponsive(app: String)
        /// 还原记录写不进去，不敢动窗口
        case recordUnwritable
        /// 屏还没好（屏幕组合还在变）
        case screenNotReady
        /// App 打不开（启动失败）
        case openFailed(app: String)
        /// App 菜单里没有「新建窗口」，或 App 没响应
        case noNewWindow(app: String)
        /// 打开了，但等满了也没有可显示的窗口（收进菜单栏的 App 常这样）
        case noWindow(app: String)
        /// 请它退出了，等满了还没退，也没有对话框：可以强制退出
        case quitStalled(app: String, pid: Int32)
        /// 换成了新型号的比例。UU 只在选屏时按屏幕尺寸开推流，比例变了要在 UU 里切走再切回来，点的位置才对（实测）
        case reshaped
        /// 换了型号，但这块屏没能换成新比例（还是原来的）；下次加屏时按新的建
        case reshapeFailed
        /// 放大过字号的窗口在 Snug 之外关掉了，放大的那几级会被 App 记住（VS Code 按工作区记），再打开时可能还大
        case zoomLeftBehind(app: String, steps: Int)
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
        /// 正在打开这个 App（启动、唤回或新建窗口），等新窗口出来；出来了转成 placing
        case opening(AppInfo)
        /// 正在把这个窗口放上来（换窗口时含放回原来那个），窗口挪好就转成 zooming
        case placing(WindowInfo)
        case puttingBack
        case zooming
        /// 正在把屏换成新型号的比例
        case reshaping
        /// 在手机上退出了这块屏，正在放回窗口、撤屏
        case dismissing
    }

    /// 窗口挪好、字号改完后等这么久再动下一步：App 要一点时间认到新的大小
    static let settleDelay: TimeInterval = 0.3
    /// 放着的窗口在 Snug 之外没了以后，等它的 App 开出新窗口最多这么久，开出来就接着放上来
    /// （ChatGPT 冷启动约 3 秒后会换掉第一个窗口，实测 11-15）
    static let replaceWait: TimeInterval = 10

    let id: ScreenID
    var behavior: ScreenBehavior {
        get { state.behavior }
        set { state.behavior = newValue }
    }
    private(set) var state = State() {
        didSet { if state != oldValue { onChange?() } }
    }
    var onChange: (() -> Void)?
    /// 这块屏还要不要：不要了（远程结束、关了开关、在手机上退出）就不再等 App 的新窗口，排在后面的撤屏不能干等
    var wanted = true

    private let env: DeskEnvironment
    private var screens: ScreenSet { env.screens }
    private var windows: any WindowControl { env.windows }
    private var timeline: any Timeline { env.timeline }
    private let ledger: RestoreRecord<PlacedRecord>
    /// 电脑屏上 Snug 挪过来的窗口和它们的账（一个窗口一份，见 SnugPaths.broughtRecord）
    private var brought: [WindowKey: PlacedRecord] = [:] {
        didSet { state.brought = Set(brought.keys) }
    }
    private var placement: Placement? {
        didSet {
            state.placed = placement.map { Placed(window: $0.window, zoom: $0.record.zoom) }
            if placement?.window.key != oldValue?.window.key { state.closeButton = nil }
        }
    }
    /// 发过几个号、排着没做的号、正在做的事（见 Ticket）
    private var issued = 0
    private var queued: [(ticket: Ticket, work: Work)] = []
    private var running: Work? {
        didSet { showWork() }
    }
    /// 刚在 Snug 之外没了的窗口：它的 App 在 replaceWait 内开出不在 known 里的新窗口，就接着放上来
    private var replaced: (pid: Int32, known: Set<WindowKey>, until: TimeInterval)?

    init(id: ScreenID, behavior: ScreenBehavior, env: DeskEnvironment) {
        self.id = id
        self.env = env
        ledger = RestoreRecord(url: env.paths.placedRecord(for: id))
        state.behavior = behavior
    }

    /// 放在这块屏上的窗口
    var placedWindow: WindowKey? { placement?.window.key }
    var placedRecord: PlacedRecord? { placement?.record }
    var watchesReplacement: Bool { replaced != nil }

    // MARK: 状态

    // MARK: 正在做的事

    /// 一个动作的号：点下去时排上（begin），轮到时开始（start），做完收掉（end）。屏上显示正在做的那个，
    /// 没在做的就显示最先排上的：后点的不冲掉先点的，先点的做完也不清掉后点的（DeskSet 的动作排一条队，一个做完再做下一个）
    struct Ticket: Hashable {
        fileprivate let number: Int
    }

    /// 点下去：排上号，前面没有别的就马上显示，提示清掉
    @discardableResult
    func begin(_ work: Work) -> Ticket {
        issued += 1
        let ticket = Ticket(number: issued)
        queued.append((ticket, work))
        state.notice = nil
        showWork()
        return ticket
    }

    /// 轮到了（在队里调用）：从排着的里拿出来，开始做
    func start(_ ticket: Ticket) {
        guard let i = queued.firstIndex(where: { $0.ticket == ticket }) else { return }
        running = queued.remove(at: i).work
    }

    /// 队里自己起的动作（自动放上屏、换比例、放在问用户的窗口）：不排号，直接开始，提示清掉
    func start(_ work: Work) {
        state.notice = nil
        running = work
    }

    /// 做的途中换阶段（打开 → 放上来 → 调字号）
    func advance(to work: Work) {
        if running != nil { running = work }
    }

    func end() { running = nil }

    /// 排了号又不用做了（换比例前又改回了原来的型号）
    func cancel(_ ticket: Ticket) {
        queued.removeAll { $0.ticket == ticket }
        showWork()
    }

    /// 轮到这个号：开始、做完、收掉
    func perform(_ ticket: Ticket, _ body: () async -> Void) async {
        start(ticket)
        await body()
        end()
    }

    /// 队里自己起的动作：开始、做完、收掉
    func perform(_ work: Work, _ body: () async -> Void) async {
        start(work)
        await body()
        end()
    }

    private func showWork() { state.work = running ?? queued.first?.work }

    func setNotice(_ notice: Notice?) { state.notice = notice }
    func showListNow() { state.listVisible = true }

    /// 屏幕模块里这块屏的状态变了。新屏从干净的提示开始：没屏时轮到的动作（比如盯着的退出排进队的放对话框）会留下提示
    func screenChanged(_ screen: ScreenSet.State) {
        if screen.display != nil, state.display == nil { state.notice = nil }
        if screen.display != nil { state.homeBarStyle = screenFit.homeBarStyle }
        state.screen = screen
    }

    // MARK: 放窗口

    /// 从别的屏转过来的窗口：跟过来的还原记录（原位记录跟着窗口走，中间不还原一次），和让那块屏交出窗口的那一下。
    /// 接手的屏把账写下了才交出：在那之前哪一步没成（够不着、自己原来那个放不回去、账写不进去），窗口都还归原来那块屏
    struct Handover {
        let record: PlacedRecord
        let release: () -> Void
    }

    /// zoom 为 false：放的是在问用户的窗口（对话框、挂着 sheet 的文档），不调字号，按键会被对话框挡下。
    /// handover：从别的屏转过来（见 DeskSet.pull）
    func place(_ window: WindowInfo, zoom: Bool = true, from handover: Handover? = nil) async {
        guard behavior.touch else { return await bring(window, from: handover) }
        let started = timeline.now
        guard let display = readyDisplay(for: "放 \(window.label)") else {
            state.notice = .screenNotReady
            return
        }
        if placement?.window.key == window.key {
            await reveal()
            return
        }
        guard let look = await clearScreen(for: window),
              var next = await recordPlacement(window, look: look, zoom: zoom, from: handover),
              let got = await land(&next) else { return }
        let was = look.fullScreen ? "（原来全屏）" : look.minimized ? "（原来最小化）" : ""
        let took = String(format: "%.1f", timeline.now - started)
        let fill = describeFill(got, in: screens.windowArea(id, withHomeBar: true), width: screens.width(id) ?? next.width)
        Log.info("\(window.label) 放上屏 #\(display)（\(took)s）：原位 \(next.record.original.short)\(was)，\(fill)")

        // 带着字号回来的不重复放大，只补差的那几级
        let steps = env.zoomBook.steps(for: window.bundleID, default: env.defaultZoom) - next.record.zoom
        guard zoom, steps != 0 else { return }
        // 窗口已经在屏上了，剩下的只是调字号
        advance(to: .zooming)
        await timeline.sleep(Self.settleDelay)
        await changeZoom(by: steps)
    }

    /// 放窗口第一段，腾出屏：先确认要放的窗口够得着，再放回屏上现在那个、上次没放回去的那个。
    /// 点到刚关掉的卡片，不能先把现在的拆了、两头落空；放回不了（App 卡住）就不放：两个窗口会叠在屏上，还原记录也只记得住一个。
    /// 成了交回要放的窗口此刻的样子（放回别的窗口可能动到它，重新读）
    private func clearScreen(for window: WindowInfo) async -> WindowLook? {
        guard await reach(window) != nil else { return nil }
        if let p = placement, await !returnToOriginal(p) {
            Log.warn("\(p.window.label) 放不回去，先不换成 \(window.label)")
            state.notice = .windowUnresponsive(app: p.window.app)
            return nil
        }
        if let stuck = await putBackLeftover() {
            Log.warn("\(stuck.label) 还放不回去，先不放 \(window.label)")
            state.notice = .windowUnresponsive(app: stuck.app)
            return nil
        }
        return await reach(window)
    }

    /// 放窗口第二段，先记账再动手：还原记录取跟过来的（转屏）、留下的账（它原样回来了：屏上关掉又在手机上重开，
    /// 原位还是当初的，字号按带回来的算），都没有就按此刻的样子新记。全屏的窗口这时读到的是全屏的位置，
    /// 崩溃后按它放回再恢复全屏也对；退出全屏后再按平时的位置改记。账写不进去就不动窗口
    private func recordPlacement(_ window: WindowInfo, look: WindowLook, zoom: Bool, from handover: Handover?) async -> Placement? {
        let inherited = handover?.record
        let known = Set(await windows.shownWindows(of: window.key.pid).map(\.key)).subtracting([window.key])
        let owed = inherited == nil ? env.leftBehind.owed(by: window, frame: look.frame) : nil
        let record = inherited ?? owed?.record ?? PlacedRecord(
            window: window.key, app: window.app, label: window.label, original: env.originalFrame(look.frame),
            wasFullScreen: look.fullScreen, wasMinimized: look.minimized, bundleID: window.bundleID, title: window.title)
        var next = Placement(window: window, record: record, width: screenFit.baseWidth, known: known, asking: !zoom)
        guard write(next.record) else {
            state.notice = .recordUnwritable
            return nil
        }
        handover?.release()
        if let owed {
            Log.info("\(window.label) 带着屏上的样子回来了，接着放：原位按当初的 \(record.original.short)，字号已大 \(record.zoom) 级")
            env.leftBehind.settle(owed)
        }
        if look.minimized { await windows.setMinimized(window.key, false) }
        if look.fullScreen {
            await windows.setFullScreen(window.key, false)
            // 退出全屏后的位置才是它平时的位置：放回时回到这里再进全屏
            if let windowed = await windows.look(window.key)?.frame, inherited == nil {
                next.record.original = env.originalFrame(windowed)
                write(next.record)
            }
        }
        return next
    }

    /// 放窗口第三段，铺上屏：先按基准宽度铺，App 卡在自己的最小尺寸上时换档再铺；这时列表还盖着（「正在打开」）。
    /// 铺不上就按账放回去、露出列表，交回 nil
    private func land(_ next: inout Placement) async -> CGRect? {
        placement = next
        guard let got = await fill(&next) else {
            let notice = await env.unreachable(next.window)
            Log.warn("\(next.window.label) 挪不上屏（\(Self.reason(notice, gone: "刚关了"))），放回去")
            placement = nil
            await putBack(next.record)
            // 露着列表：屏可能停在铺的中途换过的那一档
            await matchWidth()
            state.notice = notice
            return nil
        }
        placement = next
        await windows.focus(next.window.key)
        state.listVisible = false
        return got
    }

    /// 电脑屏：把窗口挪到这块屏上居中，大小不超过这块屏；不铺满、不调字号。先记账再动手：远端的人看不见别的屏、拖不回去，
    /// 靠资源库里的「还原」放回原处，撤屏、崩溃后也按账放回。还记着原处的（挪过来后又最小化、进了全屏）接着用原来那份，
    /// 从别的屏转过来的用跟过来的那份；挪不过来就按账放回
    private func bring(_ window: WindowInfo, from handover: Handover?) async {
        guard let area = screens.windowArea(id, withHomeBar: false) else { return state.notice = .screenNotReady }
        guard var look = await windows.look(window.key) else { return state.notice = await env.unreachable(window) }
        let kept = handover?.record ?? brought[window.key]
        var record = kept ?? PlacedRecord(
            window: window.key, app: window.app, label: window.label, original: env.originalFrame(look.frame),
            wasFullScreen: look.fullScreen, wasMinimized: look.minimized, bundleID: window.bundleID, title: window.title)
        guard write(record) else { return state.notice = .recordUnwritable }
        handover?.release()
        brought[window.key] = record
        if look.minimized { await windows.setMinimized(window.key, false) }
        if look.fullScreen {
            await windows.setFullScreen(window.key, false)
            look = await windows.look(window.key) ?? look
            // 退出全屏后的位置才是它平时的位置：放回时回到这里再进全屏
            if kept == nil {
                record.original = env.originalFrame(look.frame)
                write(record)
                brought[window.key] = record
            }
        }
        guard let got = await windows.move(window.key, to: area.centered(look.frame.size)) else {
            let notice = await env.unreachable(window)
            Log.warn("\(window.label) 挪不到屏（\(id)）上（\(Self.reason(notice, gone: "刚关了"))），按账放回")
            brought[window.key] = await putBack(record)
            return state.notice = notice
        }
        await windows.focus(window.key)
        Log.info("\(window.label) 挪到屏（\(id)）：原位 \(record.original.short)，现在 \(got.short)")
    }

    /// 电脑屏上这个窗口的账：转到别的屏时跟着走
    func broughtRecord(of window: WindowKey) -> PlacedRecord? { brought[window] }

    /// 电脑屏上的这个窗口不归这块屏管了（转到了别的屏、在 Snug 之外关了、被用户挪走了）：销掉它的账，不动窗口
    func release(_ window: WindowKey) {
        guard brought.removeValue(forKey: window) != nil else { return }
        settleRecord(ledger(for: window))
    }

    /// 电脑屏资源库里的「还原」：按账放回原处。放不回去（App 卡住）就留在屏上、账留着，提示一下，可以再点
    func putBackBrought(_ window: WindowKey) async {
        guard let record = brought[window] else { return }
        brought[window] = await putBack(record)
        if let left = brought[window] { state.notice = .windowUnresponsive(app: left.app) }
    }

    /// 把屏上的窗口交出去（接手的屏写下账的那一刻，见 Handover）：不还原，露出列表；这边的账等 transferred 再销
    func handOver() {
        placement = nil
        state.listVisible = true
    }

    /// 窗口交出去了：账由接手的屏管（铺上了接着管，没铺上已按账放回、或留着下次再放），这边的销掉，屏换回基准宽度
    func transferred() async {
        settleRecord()
        await matchWidth()
    }

    // MARK: 屏幕适配

    /// 屏此刻的比例：选档只能在屏上登记的档位里选。换比例还没轮到、或者没换成时，它和要的不一样
    private var screenFit: ScreenFit { screens.fit(id) ?? .standard }

    /// 屏该用哪一档：露着列表（或没放窗口）是基准宽度，放着窗口是它那一档
    private var wantedWidth: Int {
        guard let p = placement, !state.listVisible else { return screenFit.baseWidth }
        return p.width
    }

    /// 让屏跟上该用的那一档。电脑屏的档位不归 Snug 管：用户在「显示器」设置里选哪一档就是哪一档
    func matchWidth() async {
        guard behavior.touch, screens.display(id) != nil else { return }
        await screens.setWidth(id, wantedWidth)
    }

    /// 屏换到窗口那一档，把窗口铺满。铺不满（App 限定了最小尺寸）就按它实际的大小换到装得下的一档再铺。
    /// 换档没成时屏还是原来那一档，算出来的还是这一档，不会一直往上换。返回最后挪到的位置；挪不动（窗口关了、App 没响应）返回 nil
    @discardableResult
    private func fill(_ p: inout Placement) async -> CGRect? {
        await screens.setWidth(id, p.width)
        guard let area = screens.windowArea(id, withHomeBar: true), let got = await moveOnto(p.window, area) else { return nil }
        p.settled = got
        // App 关窗时存下的就是这个大小：窗口在 Snug 之外没了，凭它认出回来的是不是它
        p.record.filled = got
        write(p.record)
        if p.asking {
            state.closeButton = nil
        } else {
            state.closeButton = await windows.closeButton(p.window.key).map { CloseButton(frame: $0, window: p.window.key.id, windowFrame: got) }
        }
        // 原点已落在区域上（moveOnto），尺寸大于区域就是被 App 的最小尺寸夹住了
        guard let current = screens.width(id) else { return got }
        let width = screenFit.width(toFit: got.size, in: area.size, at: current)
        guard width > current, width != p.width else { return got }
        Log.info("\(p.window.label) 在 \(current) 宽的屏上铺不满（App 限定了最小尺寸，实际 \(got.short)），换到 \(width) 宽")
        p.width = width
        return await fill(&p)
    }

    /// 挪上这块屏，原点落不到区域上就交回 nil，不把留在别处的窗口当成放上了。有些 App 的窗口从远处的屏（如主屏右下方的屏）
    /// 直达会留在原处：先挪到原来那块主屏中间，App 认了当前所在的屏再挪一次（社区 PR #26，作者 yupeng316888-create）。
    /// 设着主屏时此刻的主屏可能就是这块屏，所以中转用原来那块
    private func moveOnto(_ window: WindowInfo, _ area: CGRect) async -> CGRect? {
        guard let first = await windows.move(window.key, to: area) else { return nil }
        if Self.landed(first, on: area) { return first }
        guard let home = screens.homeMainArea(), let staged = await windows.move(window.key, to: home.centered(first.size)),
              home.contains(CGPoint(x: staged.midX, y: staged.midY)) else {
            Log.warn("\(window.label) 没挪到屏上（实际 \(first.short)），挪到原主屏中转也不成")
            return nil
        }
        guard let got = await windows.move(window.key, to: area), Self.landed(got, on: area) else {
            Log.warn("\(window.label) 没挪到屏上（实际 \(first.short)），经原主屏中转仍挪不上")
            return nil
        }
        Log.info("\(window.label) 直达没挪到屏上（实际 \(first.short)），经原主屏中转挪上了")
        return got
    }

    private static func landed(_ frame: CGRect, on area: CGRect) -> Bool {
        abs(frame.minX - area.minX) < 2 && abs(frame.minY - area.minY) < 2
    }

    /// 收起列表、露出屏上的窗口：先换到它那一档、重新铺满，再收列表、激活它。
    /// 换档时列表还盖着，手机上看不到窗口被挪来挪去
    func reveal() async {
        guard screens.display(id) != nil, let p = placement else { return }
        // 先换档：App 一时读不到时 refill 什么都不做，档位也得对；换档触发的复查会在 App 恢复后补铺
        await screens.setWidth(id, p.width)
        await refill(because: "回到窗口")
        state.listVisible = false
        await windows.focus(p.window.key)
    }

    /// 屏幕配置变了：屏还是不是该用的那一档、窗口还铺不铺满
    func recheck() async {
        guard screens.display(id) != nil else { return }
        if state.listVisible { await matchWidth() } else { await refill(because: "屏幕配置变了") }
    }

    /// 窗口没铺好就重新铺：屏不在它那一档（刚从列表回来、换档没成、系统改了模式），
    /// 或者窗口被挪动、撑大了（换档时系统会挪它；终端类 App 调字号时会按行列数撑大窗口）。
    /// 跟上次挪完的样子比，不跟可放区域比：比最宽一档还宽的窗口本来就铺不满，再挪也一样
    private func refill(because reason: String) async {
        guard screens.display(id) != nil, var p = placement, let frame = await windows.look(p.window.key)?.frame else { return }
        let moved = p.settled.map { !frame.matches($0) } ?? true
        guard moved || screens.width(id) != p.width else { return }
        let what = moved ? "变成了 \(frame.short)" : "要的 \(p.width) 宽不是屏现在这一档"
        Log.info("\(reason)，\(p.window.label) \(what)，重新铺满")
        await fill(&p)
        placement = p
    }

    /// 换了型号的比例：ok 为 false 时屏还是原来的档位，之后照旧按屏上的比例选档
    func reshaped(_ ok: Bool) async {
        guard ok else {
            state.notice = .reshapeFailed
            return
        }
        state.homeBarStyle = screenFit.homeBarStyle
        state.notice = .reshaped
        guard var p = placement else { return }
        // 窗口要的档位按新比例从基准宽度重新找；忘掉上次挪完的样子，露出来时一定重新铺
        p.width = screenFit.baseWidth
        p.settled = nil
        if !state.listVisible {
            Log.info("换了比例，\(p.window.label) 按新比例重新铺满")
            await fill(&p)
        }
        placement = p
    }

    // MARK: 放回

    /// 放回原位、回到 App 资源库，返回放回去了没有。restoringState 为 false 时不恢复全屏、最小化（马上要关的窗口）。
    /// 没放回去时窗口还在屏上，照旧算放着（字号按实际缩回了多少算），还原记录也留着
    func returnToOriginal(restoringState: Bool = true) async -> Bool {
        guard let p = placement else { return true }
        return await returnToOriginal(p, restoringState: restoringState)
    }

    private func returnToOriginal(_ p: Placement, restoringState: Bool = true) async -> Bool {
        if let left = await putBack(p.record, restoringState: restoringState) {
            var p = p
            p.record = left
            placement = p
            return false
        }
        placement = nil
        state.listVisible = true
        return true
    }

    /// 放回屏上的窗口（小横条上的「还原」）。放不回去（App 卡住）就留在屏上，提示一下，可以再点
    func putBackPlaced() async {
        if let p = placement, await !returnToOriginal(p) {
            state.notice = .windowUnresponsive(app: p.window.app)
        }
        await matchWidth()
    }

    /// 屏要撤了：放回窗口，屏上不再算有窗口；放不回去的留着还原记录，下次放窗口或下次启动再放。
    /// 电脑屏上挪过来的还记着账的都放回（关了的 putBack 自己销账）。这时不按位置判断是不是被用户挪走了：
    /// 撤之前先设回原主屏，系统会把新主屏上的窗口整体搬回原主屏，看上去像挪走了；用户自己挪走的，定期核对时已经销了
    func vacate() async {
        if let p = placement { await putBack(p.record) }
        placement = nil
        for key in brought.keys.sorted(by: Self.order) {
            if let record = brought[key] { await putBack(record) }
        }
        brought = [:]
        state.listVisible = true
        state.notice = nil
    }

    /// 按记录放回：缩回字号（窗口还在屏上、还是它 App 的当前窗口；缩完马上记账）→ 挪回原位 →
    /// 原来全屏的恢复全屏、原来最小化的再最小化。放回了就销账、窗口确实没了就转成留下的账，返回 nil；
    /// 窗口还在却缩不回、挪不动（App 没响应、没有权限）就留着记录（下次放窗口或下次启动再放），返回留下的这条
    @discardableResult
    func putBack(_ record: PlacedRecord, restoringState: Bool = true) async -> PlacedRecord? {
        var record = record
        let zoom = record.zoom
        if zoom != 0 {
            // 缩不回就先不挪：挪回原位就销账了，多出来的字号再也没人缩
            guard await windows.zoom(record.window, steps: -zoom) else { return await stuckOrGone(record, "缩不回字号") }
            record.zoom = 0
            write(record)
        }
        let target = env.screens.currentFrame(record.original)
        guard let got = await windows.move(record.window, to: target) else {
            return await stuckOrGone(record, "挪不动")
        }
        if restoringState, record.wasFullScreen {
            await timeline.sleep(Self.settleDelay)
            await windows.setFullScreen(record.window, true)
        } else if restoringState, record.wasMinimized {
            await windows.setMinimized(record.window, true)
        }
        settleRecord(ledger(for: record.window))
        if got.matches(target) {
            let restored = !restoringState ? "" : record.wasFullScreen ? "并恢复全屏" : record.wasMinimized ? "并最小化" : ""
            Log.info("\(record.label) 已放回原位\(restored)\(zoom != 0 ? "，字号缩回 \(zoom) 级" : "")")
        } else {
            Log.warn("\(record.label) 放回没对上：目标 \(target.short)，实际 \(got.short)")
        }
        return nil
    }

    /// 上次没放回去的窗口（Snug 崩溃，或 App 卡住没放成）：按还原记录放回去。
    /// 放下一个窗口之前必须先做，不然新记录会把它的原位和字号永远盖掉。返回仍然放不回去的那条
    @discardableResult
    func putBackLeftover() async -> PlacedRecord? {
        guard placement == nil, let record = ledger.pending() else { return nil }
        guard await windows.exists(record.window) else {
            Log.info("还原记录里的 \(record.label) 已经不在了（App 退出或窗口关了），等它回来再还")
            await leaveBehind(record)
            return nil
        }
        Log.info("\(record.label) 上次没放回去，现在放回 \(record.original.short)")
        return await putBack(record)
    }

    /// 放回时有一步做不了：窗口还在就留着记录、返回这条，确实没了就转成留下的账
    private func stuckOrGone(_ record: PlacedRecord, _ what: String) async -> PlacedRecord? {
        if await windows.exists(record.window) {
            Log.warn("\(record.label) 还在，但\(what)（App 没响应或没有辅助功能权限），还原记录留着，稍后再放回")
            return record
        }
        Log.info("\(record.label) 已经关了，等它回来再还")
        await leaveBehind(record)
        return nil
    }

    /// 窗口在 Snug 之外没了：账不销，转成留下的账（见 LeftBehindLedger.add）。
    /// 先记下留下的账再销这块屏的账：中途崩溃最多多一笔账，不会丢账
    private func leaveBehind(_ record: PlacedRecord) async {
        // 没铺过、没调过字号（电脑屏挪过来的、还没铺上就没了的）：App 存下的就是原来的样子，没有要还的，直接销账
        if record.filled != nil || record.zoom != 0, let notice = await env.leftBehind.add(record) { state.notice = notice }
        settleRecord(ledger(for: record.window))
    }

    // MARK: 核对

    /// 要不要核对：放着窗口（电脑屏是挪过来的还记着账）、没在做别的
    var needsVerify: Bool { (placement != nil || !brought.isEmpty) && state.work == nil }

    /// 定期核对（DeskSet 排进队里调）：屏上的窗口被关掉了，就回到 App 资源库。只认窗口服务器的结论：App 一时没响应不算关了。
    /// 窗口还在却不在屏上（被最小化、App 被隐藏、关成了隐藏），屏上只剩空桌面：也回到列表，
    /// 但它照旧算放着、还原记录留着，可以返回它、还原或换一个
    func verify() async {
        guard behavior.touch else { return await verifyBrought() }
        guard let p = placement else { return }
        guard await windows.exists(p.window.key) else {
            Log.info("屏上的 \(p.window.label) 在 Snug 之外关了，回到 App 资源库")
            placement = nil
            state.listVisible = true
            replaced = (p.window.key.pid, p.known.union([p.window.key]), timeline.now + Self.replaceWait)
            await leaveBehind(p.record)
            await matchWidth()
            return
        }
        if !state.listVisible, await !windows.isShown(p.window.key) {
            Log.info("屏上的 \(p.window.label) 不在屏上了（最小化、隐藏或关成了隐藏），回到 App 资源库")
            state.listVisible = true
            await matchWidth()
        }
    }

    /// 设主屏、取消主屏时系统在原主屏和新主屏之间整体互换窗口（V11）：这块屏留着，Snug 放上来、挪过来的窗口却被换去了别的屏，
    /// 挪回来。不挪的话界面还当它在屏上（资源库开着时不会自己铺回来），电脑屏上的会被定期核对当成用户自己挪走、销掉账
    func reclaimSwapped() async {
        guard let bounds = screens.bounds(id) else { return }
        func away(_ look: WindowLook) -> Bool { !look.minimized && !bounds.contains(CGPoint(x: look.frame.midX, y: look.frame.midY)) }
        if var p = placement, let look = await windows.look(p.window.key), away(look) {
            Log.info("换主屏时系统把 \(p.window.label) 换到了别的屏（\(look.frame.short)），挪回屏上")
            await fill(&p)
            placement = p
        }
        guard !brought.isEmpty, let area = screens.windowArea(id, withHomeBar: false) else { return }
        for key in brought.keys.sorted(by: Self.order) {
            guard let record = brought[key], let look = await windows.look(key), away(look) else { continue }
            Log.info("换主屏时系统把 \(record.label) 换到了别的屏（\(look.frame.short)），挪回电脑屏")
            if await windows.move(key, to: area.centered(look.frame.size)) == nil { Log.warn("\(record.label) 挪不回电脑屏") }
        }
    }

    /// 电脑屏：挪过来的窗口在 Snug 之外关了、或被挪去了别的屏，销掉它的账。关了没有要还的（大小没改、字号没调），
    /// 挪走了是用户自己安排好了，不再拽回来。最小化的照旧算在这块屏上；读不到位置（App 一时没响应）的先不动
    private func verifyBrought() async {
        guard !brought.isEmpty, let bounds = screens.bounds(id) else { return }
        for key in brought.keys.sorted(by: Self.order) {
            guard let record = brought[key] else { continue }
            guard await windows.exists(key) else {
                Log.info("电脑屏上的 \(record.label) 在 Snug 之外关了，不再记着原处")
                release(key)
                continue
            }
            guard let look = await windows.look(key), !look.minimized,
                  !bounds.contains(CGPoint(x: look.frame.midX, y: look.frame.midY)) else { continue }
            Log.info("电脑屏上的 \(record.label) 被挪去了别的屏（\(look.frame.short)），不再拽回来")
            release(key)
        }
    }

    /// 刚在 Snug 之外没了的窗口，它的 App 开出了新窗口（不在放上来时就有的那些里）：接着放上来。
    /// 用户已经放了别的窗口、或等满了，就不再等
    func followReplacement() async {
        guard let r = replaced else { return }
        guard placement == nil, timeline.now < r.until else {
            replaced = nil
            return
        }
        guard screens.display(id) != nil, let next = await windows.shownWindows(of: r.pid).first(where: { !r.known.contains($0.key) }) else { return }
        Log.info("\(next.app) 换了个窗口，接着放上屏：\(next.label)")
        if await placeOnItsOwn(next) { replaced = nil }
    }

    /// 后台自动放上屏（App 换了个窗口、窗口回到了屏上）：用户已经点了别的动作就让出，返回 false；
    /// 照放窗口的样子显示「正在打开」
    @discardableResult
    func placeOnItsOwn(_ window: WindowInfo) async -> Bool {
        guard state.work == nil else { return false }
        await perform(.placing(window)) { await place(window) }
        return true
    }

    /// 空着、等着接回来的窗口：还在远程、屏上空着
    var awaitsReturn: Bool { wanted && placement == nil && screens.display(id) != nil }

    // MARK: 字号

    /// 字大 / 字小一级，并记到这个 App 名下
    func zoom(by delta: Int) async {
        if await changeZoom(by: delta), let p = placement, let bundle = p.window.bundleID {
            env.zoomBook.remember(p.record.zoom, for: bundle)
            env.saveZoomBook()
        }
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
            state.notice = await env.unreachable(p.window)
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

    /// 可以放窗口的屏；没好时写明是哪一步没好
    func readyDisplay(for what: String) -> DisplayID? {
        guard let display = screens.display(id) else {
            Log.warn("\(what)：屏（\(id)）没好（\(state.screen)）")
            return nil
        }
        guard screens.windowArea(id, withHomeBar: behavior.touch) != nil else {
            Log.warn("\(what)：读不到屏 #\(display) 的可放区域（屏幕组合可能还在变）")
            return nil
        }
        return display
    }

    /// 铺满了没有、用的哪一档。没铺满是 App 要的比最宽一档还宽，或者换档没成（见前面的日志）
    private func describeFill(_ got: CGRect, in area: CGRect?, width: Int) -> String {
        let screen = width == screenFit.baseWidth ? "" : "（屏 \(width) 宽）"
        if let area, got.matches(area) { return "已铺满\(screen)" }
        return "没铺满\(screen)，实际 \(got.short)"
    }

    /// 读要放的窗口；读不到就提示是关了还是 App 没响应
    private func reach(_ window: WindowInfo) async -> WindowLook? {
        if let look = await windows.look(window.key) { return look }
        let notice = await env.unreachable(window)
        Log.warn("读不到 \(window.label)（\(Self.reason(notice, gone: "已经关了"))），不放")
        state.notice = notice
        return nil
    }

    /// 日志里的原因
    static func reason(_ notice: Notice, gone: String) -> String {
        if case .windowGone = notice { gone } else { "App 没响应或没有辅助功能权限" }
    }

    /// 这笔账记在哪：触屏一块屏一份，电脑屏挪过来的窗口一个一份
    private func ledger(for window: WindowKey) -> RestoreRecord<PlacedRecord> {
        behavior.touch ? ledger : RestoreRecord(url: env.paths.broughtRecord(for: id, window: window))
    }

    /// 挪过来的几个窗口按固定的顺序处理，日志和测试都好对
    private static func order(_ a: WindowKey, _ b: WindowKey) -> Bool { (a.pid, a.id) < (b.pid, b.id) }

    @discardableResult
    func write(_ record: PlacedRecord) -> Bool {
        do {
            try ledger(for: record.window).record(record)
            return true
        } catch {
            Log.error("还原记录写不进去（\(record.label)）：\(error)")
            return false
        }
    }

    private func settleRecord(_ ledger: RestoreRecord<PlacedRecord>? = nil) {
        do {
            try (ledger ?? self.ledger).settle()
        } catch {
            // 删不掉的记录下次启动会再还原一次：窗口已经在原位，再挪一次也是原位
            Log.error("还原记录删不掉：\(error)")
        }
    }
}

/// 放在屏上的那个窗口：它的还原记录（写进盘里的就是这一份，不另抄字段）、它要的那一档和上次挪完的样子
private struct Placement {
    let window: WindowInfo
    var record: PlacedRecord
    /// 屏用哪一档（ScreenFit）：先按基准宽度，铺不满时换成装得下它的一档
    var width: Int
    /// 上次挪完的样子：比最宽一档还宽的窗口铺不满，以它为准判断窗口有没有被再挪动
    var settled: CGRect?
    /// 放上来时它的 App 已经开着的其它窗口：它在 Snug 之外没了以后，不在这里面的才算 App 换上的新窗口
    var known: Set<WindowKey> = []
    /// 在问用户的窗口（挂着「要存储吗」）：不调字号，也不拦它的关闭按钮
    var asking = false
}
