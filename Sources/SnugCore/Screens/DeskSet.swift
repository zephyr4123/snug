// 多块屏的总管：要哪些屏（setWishes）、各块屏上的动作、App 级的动作，都排进同一条队（SerialLane），
// 屏的增删和窗口的挪动不会交错，也不会两块屏抢着挪同一个窗口。
// - 屏：先给要撤的屏清场（屏上放着的窗口按账放回），再交给 ScreenSet 做差量，最后给新屏建 Desk
// - 带屏号的意图转给那块屏的 Desk；窗口放在别的屏上时先从那块屏转过来（原位记录跟着窗口走，中间不还原一次）
// - App 级的动作在这里：打开、新建窗口时等新窗口出来再放；退出 App 前先把它在所有屏上的窗口放回原位；
//   退出 App、关窗口的请求发出之后不占着队等结果（Electron 类 App 退出要五六秒，「要存储吗」要等人回答），
//   另起一个盯着，期间别的动作照做；盯到对话框时再排进队把它放上发起的那块屏
// - 共用的账：字号簿、留下的账（DeskEnvironment）；启动时按各屏的还原账还原（recover），等窗口回来再还（checkReturns）
import CoreGraphics
import Foundation

@MainActor
public final class DeskSet {
    public struct State: Equatable, Sendable {
        /// 要的每块屏上的状态
        public var desks: [ScreenID: Desk.State] = [:]
        /// 已经请它退出、还在等它退完的 App（进程号）。每块屏的 App 资源库都显示
        public var quitting: Set<Int32> = []
        /// 已经请它关掉、还在等它关上的窗口
        public var closing: Set<WindowKey> = []
        /// 在手机上退出了的屏：这次远程不再加（见 dismissScreen）
        public var dismissed: Set<ScreenID> = []

        public init() {}
    }

    /// 盯着的 App 退完了、窗口关上了
    public enum Gone: Equatable, Sendable {
        case app(Int32)
        case window(WindowKey)
    }

    /// 屏幕配置一变，过这么久再检查一次（等系统折腾完）
    static let recheckDelay: TimeInterval = 1.5
    /// 等新窗口出来时隔多久问一次（实测一次不到 1 毫秒）
    static let windowPoll: TimeInterval = 0.1
    /// 冷启动最多等多久出窗口（实测 ChatGPT 6.6 秒，更重的 App 更慢）；唤回、新建窗口实测都在 0.3 秒内，等 10 秒
    static let launchWait: TimeInterval = 30
    static let windowWait: TimeInterval = 10
    /// 最多等多久才算没动静：退出给强制退出（实测 Electron 类 App 退出要五六秒），关窗口提示无响应
    static let quitWait: TimeInterval = 10
    static let closeWait: TimeInterval = 5
    /// 给了强制退出以后再看这么久、隔 stalledPoll 看一次：它自己退了（大型 App 退出要十几秒），提示就撤掉
    static let stalledFollow: TimeInterval = 60
    static let stalledPoll: TimeInterval = 1

    public private(set) var state = State() {
        didSet { if state != oldValue { onChange?(state) } }
    }
    public var onChange: ((State) -> Void)?
    /// 确认 App 退完、窗口关上的那一刻，在撤掉「正在退出 / 正在关闭」之前：数据源据此马上去掉它，
    /// 不然要等下一轮刷新，卡片会以原样闪回一下
    public var onGone: ((Gone) -> Void)?
    /// 即将加屏、撤屏，或把被拨动的别的屏设回去：会话层据此暂缓断开判定（屏幕一变，UU 的信号会抖一下）
    public var onTopologyChange: (() -> Void)? {
        get { screens.onTopologyChange }
        set { screens.onTopologyChange = newValue }
    }

    private let screens: ScreenSet
    private let env: DeskEnvironment
    private let lane = SerialLane()
    private var windows: any WindowControl { env.windows }
    private var apps: any AppControl { env.apps }
    private var timeline: any Timeline { env.timeline }
    /// 要的屏（扣掉在手机上退出了的），按屏幕列表的顺序
    private var wishes: [ScreenWish] = []
    private var desks: [ScreenID: Desk] = [:]
    private var recheckGeneration = 0
    private var pendingRecheck: Task<Void, Never>?
    /// 盯着退出、关窗请求的结果
    private let watcher: RequestWatcher
    /// 在手机上退出、换了型号时马上排上的号（见 Desk.Ticket），轮到 reconcile 时开始、撤完换完收掉
    private var dismissTickets: [ScreenID: Desk.Ticket] = [:]
    private var reshapeTickets: [ScreenID: Desk.Ticket] = [:]

    public init(displays: any VirtualDisplays, windows: any WindowControl, apps: any AppControl, arrangement: any DisplayArrangement,
                timeline: any Timeline = SystemTimeline(), paths: SnugPaths, defaultZoom: Int = 2) {
        screens = ScreenSet(displays: displays, windows: windows, arrangement: arrangement, timeline: timeline, lane: lane)
        watcher = RequestWatcher(windows: windows, timeline: timeline)
        env = DeskEnvironment(windows: windows, apps: apps, timeline: timeline, screens: screens,
                              paths: paths, defaultZoom: defaultZoom)
        // 弱引用：ScreenSet 的重试排在计时上，可能比 DeskSet 活得久
        screens.placedWindows = { [weak self] in Set(self?.desks.values.compactMap(\.placedWindow) ?? []) }
        screens.onChange = { [weak self] in
            guard let self else { return }
            for (id, desk) in desks { desk.screenChanged(screens.states[id] ?? .off) }
        }
    }

    // MARK: 要哪些屏

    /// 此刻要哪些屏（ScreenPlan 的结论）。变了才动：新的建出来，不要的先放回窗口再撤，型号变了的在线换比例。
    /// 不再要的屏不再算在手机上退出过：下次要时照常加
    public func setWishes(_ incoming: [ScreenWish]) {
        state.dismissed.formIntersection(Set(incoming.map(\.id)))
        let next = incoming.filter { !state.dismissed.contains($0.id) }
        guard next != wishes else { return }
        let previous = wishes
        wishes = next
        let ids = Set(next.map(\.id))
        for (id, desk) in desks where !ids.contains(id) { desk.wanted = false }
        for wish in next {
            if let desk = desks[wish.id] {
                desk.behavior = wish.behavior
                desk.wanted = true
                // 换了型号：闲着就马上盖上「正在调整」；别的动作在做时不冲掉它的状态，轮到换比例时再设
                if let old = previous.first(where: { $0.id == wish.id }), old.fit != wish.fit, desk.state.work == nil, desk.state.display != nil {
                    reshapeTickets[wish.id] = desk.begin(.reshaping)
                }
            } else {
                addDesk(for: wish)
            }
        }
        lane.run { await self.reconcile() }
    }

    /// 在手机上退出了某块屏：放回窗口、撤掉这块屏，直到不再要它之前都不再加（这次远程结束、关了开关）。
    /// 没接显示器的 Mac 上，Snug 的屏一出现系统就撤掉自己的默认屏，UU远程 里没有别的屏可切，靠它回到原来的画面（issue #8）。
    /// 远程刚结束、屏还没撤完时点的不算：不然会挡掉下一次远程的屏
    public func dismissScreen(_ id: ScreenID) {
        guard let desk = desks[id], desk.wanted else { return }
        state.dismissed.insert(id)
        wishes.removeAll { $0.id == id }
        desk.wanted = false
        Log.info("在手机上退出了屏（\(id)）：放回窗口、撤屏，这次远程不再加")
        dismissTickets[id] = desk.begin(.dismissing)
        lane.run { await self.reconcile() }
    }

    private func addDesk(for wish: ScreenWish) {
        let desk = Desk(id: wish.id, behavior: wish.behavior, env: env)
        desk.onChange = { [weak self, weak desk] in
            guard let self, let desk, desks[desk.id] === desk else { return }
            state.desks[desk.id] = desk.state
        }
        desks[wish.id] = desk
        desk.screenChanged(screens.states[wish.id] ?? .off)
        state.desks[wish.id] = desk.state
    }

    /// 在队里按此刻的 wishes 对一遍：要撤的屏先清场，再交给 ScreenSet 建撤、换比例，最后收掉不要的 Desk
    private func reconcile() async {
        let target = wishes
        let ids = Set(target.map(\.id))
        // 设了主屏的那块要撤（或不再当主屏）：先设回原主屏，跟过去的窗口回去了，剩下的才清场
        await screens.releaseMain(keeping: target)
        let leaving = desks.values.filter { !ids.contains($0.id) && screens.display($0.id) != nil }
        // 在手机上退出的那块：「正在退出」一直显示到撤完（Desk 收掉，或又被要回来时在下面收号）
        var busy: [Desk] = []
        for desk in leaving {
            if let ticket = dismissTickets.removeValue(forKey: desk.id) {
                desk.start(ticket)
                busy.append(desk)
            }
            if let display = screens.display(desk.id) { await desk.vacate(from: display) }
            await clear(desk.id)
        }
        for wish in target where screens.display(wish.id) != nil && screens.fit(wish.id) != wish.fit {
            guard let desk = desks[wish.id] else { continue }
            if let ticket = reshapeTickets.removeValue(forKey: wish.id) { desk.start(ticket) } else { desk.start(.reshaping) }
            busy.append(desk)
        }
        // 排了号又用不着了：退出时屏已经不在、换比例前又改回了原来的型号
        for (id, ticket) in dismissTickets.merging(reshapeTickets, uniquingKeysWith: { first, _ in first }) { desks[id]?.cancel(ticket) }
        dismissTickets = [:]
        reshapeTickets = [:]
        let reshaped = await screens.apply(target)
        // 收 Desk 按「此刻」要不要判断，不按开头拷下的 target：撤屏途中（清场、等最短在线时间、等系统摆好）
        // setWishes 可能又把这块屏要了回来，它看 Desk 还在就不再建，这里删了，下一轮建出来的屏就没有 Desk
        let wanted = Set(wishes.map(\.id))
        for id in desks.keys where !wanted.contains(id) && screens.states[id] == nil {
            desks[id] = nil
            state.desks[id] = nil
        }
        for (id, ok) in reshaped { await desks[id]?.reshaped(ok) }
        for desk in busy { desk.end() }
        guard desks.isEmpty else { return }
        // 这次远程的提示、没盯完的退出和关窗不带到下一次（App 照样在退，只是不再盯）
        watcher.unwatchAll()
        state.quitting = []
        state.closing = []
    }

    /// 撤屏前清场（docs/how-it-works.md「Snug 的屏」）：Snug 放上去的已经按账放回，屏上剩下的（用户在这块屏上直接开的、
    /// 设主屏时跟过来的）挪到主屏，居中、大小不超过主屏。不挪的话，撤屏后它们停在所有屏的范围之外，系统不挪回来（实测）。
    /// 设回原主屏没成功时，主屏还是要撤的这块：挪到原来的主屏上，撤掉后系统把它摆回主屏，窗口跟着走
    private func clear(_ id: ScreenID) async {
        guard let bounds = screens.bounds(id), var main = screens.mainArea() else { return }
        if main.intersects(bounds), let home = screens.homeMainArea() { main = home }
        let stranded = await windows.windows(in: bounds)
        guard !stranded.isEmpty else { return }
        guard !main.intersects(bounds) else {
            return Log.warn("撤屏（\(id)）前屏上还有 \(stranded.count) 个窗口，主屏就是这块、找不到原来的主屏，挪不走")
        }
        var moved = 0
        for (key, frame) in stranded.sorted(by: { ($0.key.pid, $0.key.id) < ($1.key.pid, $1.key.id) }) {
            guard !screens.isWaitingToReturn(key), !screens.wasOnDesktopBeforeMirroring(key) else { continue }
            moved += 1
            let target = main.centered(frame.size)
            if await windows.move(key, to: target) == nil { Log.warn("撤屏前挪不走 pid \(key.pid) 的窗口 \(key.id)（\(frame.short)）") }
        }
        if moved > 0 { Log.info("撤屏（\(id)）前把屏上剩下的 \(moved) 个窗口挪到主屏") }
    }

    // MARK: 屏上的意图

    /// 把这个窗口放上这块屏（原来那个先放回原位）。正在退出的 App 的窗口不放：它退完会记住屏上那个窄位置。
    /// 窗口正放在别的屏上就转过来；电脑屏只把窗口挪过来，不铺满、不调字号
    public func pull(_ window: WindowInfo, on id: ScreenID) {
        guard !state.quitting.contains(window.key.pid) else { return Log.info("\(window.app) 正在退出，不放 \(window.label)") }
        guard let desk = desks[id] else { return }
        let ticket = desk.begin(.placing(window))
        lane.run { await desk.perform(ticket) { await self.place(window, on: desk) } }
    }

    /// 跨屏的那一段在这里：窗口正放在别的屏上，转到手机、平板屏是原位记录跟着走（中间不还原一次）；
    /// 转到电脑屏先在原来那块屏上放回原位、缩回字号（电脑屏不调字号）。从电脑屏转走，原位记录同样跟着走。
    /// 这块屏上怎么放归 Desk.place
    private func place(_ window: WindowInfo, on desk: Desk, zoom: Bool = true) async {
        guard !screens.isWaitingToReturn(window.key) else { return desk.setNotice(.screenNotReady) }
        if let lender = desks.values.first(where: { $0 !== desk && $0.state.brought.contains(window.key) }),
           let record = lender.broughtRecord(of: window.key) {
            Log.info("\(window.label) 从电脑屏（\(lender.id)）转到屏（\(desk.id)），原位记录跟着走")
            return await desk.place(window, zoom: zoom, from: Desk.Handover(record: record, release: { lender.release(window.key) }))
        }
        guard let from = holder(of: window.key), from !== desk else { return await desk.place(window, zoom: zoom) }
        guard desk.readyDisplay(for: "把 \(window.label) 转过来") != nil else { return desk.setNotice(.screenNotReady) }
        guard desk.behavior.touch else {
            guard await from.returnToOriginal(restoringState: false) else { return desk.setNotice(.windowUnresponsive(app: window.app)) }
            await from.matchWidth()
            return await desk.place(window, zoom: zoom)
        }
        guard let record = from.placedRecord else { return }
        Log.info("\(window.label) 从屏（\(from.id)）转到屏（\(desk.id)），原位记录跟着走")
        await desk.place(window, zoom: zoom, from: Desk.Handover(record: record, release: from.handOver))
        // 还认着就是没接住（接手的屏写账之前哪一步没成），窗口原样留在这边
        if from.placedWindow != window.key { await from.transferred() }
    }

    /// 放着这个窗口的屏
    private func holder(of window: WindowKey) -> Desk? {
        desks.values.first { $0.placedWindow == window }
    }

    /// 打开 App，等它的新窗口出来放上这块屏：没在跑就启动，在跑但没窗口就唤回（点在跑且有窗口的 App 是 pull，见 AppList.action）
    public func open(_ app: AppInfo, on id: ScreenID) {
        guard let desk = desks[id] else { return }
        let ticket = desk.begin(.opening(app))
        lane.run { await desk.perform(ticket) { await self.openWindow(of: app, newWindowIn: nil, on: desk) } }
    }

    /// 给在跑的 App 新建一个窗口（菜单里的 ⌘N），放上这块屏：从出现起就是屏的宽度，终端不会因为尺寸剧变重排
    public func newWindow(_ app: RunningApp, on id: ScreenID) {
        guard !state.quitting.contains(app.pid) else { return Log.info("\(app.app.name) 正在退出，不新建窗口") }
        guard let desk = desks[id] else { return }
        let ticket = desk.begin(.opening(app.app))
        lane.run { await desk.perform(ticket) { await self.openWindow(of: app.app, newWindowIn: app.pid, on: desk) } }
    }

    /// 关掉这块屏上的提示（「稍后」）。没退出的那个就不再盯了
    public func dismissNotice(on id: ScreenID) {
        guard let desk = desks[id] else { return }
        if case .quitStalled(_, let pid) = desk.state.notice { watcher.unwatch(.quit(pid)) }
        desk.setNotice(nil)
    }

    /// 底部小横条：回到 App 资源库（马上露出来），屏换回基准宽度。
    /// 提示留着：列表收着时出的错（比如调字号没成），这时才看得到
    public func showList(on id: ScreenID) {
        guard let desk = desks[id] else { return }
        desk.showListNow()
        lane.run { await desk.matchWidth() }
    }

    /// 列表左上角的返回键：回到屏上的窗口。换档要一会儿，期间和放窗口一样显示「正在打开」、列表点不了
    public func returnToPlaced(on id: ScreenID) {
        guard let desk = desks[id], let placed = desk.state.placed else { return }
        let ticket = desk.begin(.placing(placed.window))
        lane.run { await desk.perform(ticket) { await desk.reveal() } }
    }

    /// 把屏上的窗口放回原位
    public func putBack(on id: ScreenID) {
        guard let desk = desks[id], desk.state.placed != nil else { return }
        let ticket = desk.begin(.puttingBack)
        lane.run { await desk.perform(ticket) { await desk.putBackPlaced() } }
    }

    /// 电脑屏资源库里的「还原」：把 Snug 挪过来的这个窗口放回原处
    public func putBack(_ window: WindowKey, on id: ScreenID) {
        guard let desk = desks[id], desk.state.brought.contains(window) else { return }
        let ticket = desk.begin(.puttingBack)
        lane.run { await desk.perform(ticket) { await desk.putBackBrought(window) } }
    }

    /// 字大 / 字小一级，并记到这个 App 名下。到了上下限什么都不做（界面上那个按钮已经点不了）
    public func zoom(by delta: Int, on id: ScreenID) {
        guard let desk = desks[id], let placed = desk.state.placed, placed.zoomable,
              (placed.zoom + delta).clamped(to: ZoomBook.range) != placed.zoom else { return }
        let ticket = desk.begin(.zooming)
        lane.run { await desk.perform(ticket) { await desk.zoom(by: delta) } }
    }

    /// 设置里改了默认级数：以它为准，各 App 记住的级数一起清掉（不然改了看起来不起作用）
    public func setDefaultZoom(_ steps: Int) {
        env.defaultZoom = steps
        guard !env.zoomBook.remembered.isEmpty else { return }
        env.zoomBook.forgetAll()
        env.saveZoomBook()
    }

    // MARK: App 级的动作

    /// 退出 App（同 ⌘Q）。屏上放着它的窗口就先还原（App 退出时会记住窗口位置，不先放回下次就是屏那么窄），
    /// 放不回去就不退。请它退出后另起一个盯着：退完了就好；弹出「要存储吗」就把那个窗口放上发起的那块屏，在手机上就能选；
    /// 等满了还没退、也没有对话框，提示可以强制退出
    public func quit(_ app: RunningApp, from id: ScreenID) {
        guard !state.quitting.contains(app.pid) else { return }
        desks[id]?.setNotice(nil)
        state.quitting.insert(app.pid)
        lane.run {
            for desk in self.desks.values where desk.placedWindow?.pid == app.pid {
                let window = desk.state.placed?.window
                guard await desk.returnToOriginal() else {
                    Log.warn("\(window?.label ?? app.app.name) 放不回去，先不退出 \(app.app.name)")
                    self.state.quitting.remove(app.pid)
                    self.desks[id]?.setNotice(.windowUnresponsive(app: window?.app ?? app.app.name))
                    return
                }
                await desk.matchWidth()
            }
            Log.info("请 \(app.app.name) 退出")
            guard await self.apps.quit(pid: app.pid) else {
                self.state.quitting.remove(app.pid)
                self.desks[id]?.setNotice(.windowUnresponsive(app: app.app.name))
                return
            }
            self.watchQuit(app, from: id)
        }
    }

    /// 强制退出（提示里的按钮）：未存储的内容会丢
    public func forceQuit(pid: Int32, app: String, from id: ScreenID) {
        desks[id]?.setNotice(nil)
        watcher.unwatch(.quit(pid))
        Log.warn("强制退出 \(app)（pid \(pid)）")
        lane.run {
            if await !self.apps.forceQuit(pid: pid) { self.desks[id]?.setNotice(.windowUnresponsive(app: app)) }
        }
    }

    /// 关掉一个窗口（同点它的红色关闭按钮）。放在屏上的先还原位置和字号（App 会记住关掉的窗口在哪、多大，
    /// 不先放回，下次开出来就是屏那么窄），但不恢复全屏：马上就要关了。全屏的先退出全屏，
    /// 不然按关闭按钮没反应（实测 11-14，不论在不在当前桌面空间）。之后另起一个盯着，同退出：
    /// 关掉了就好；问「要存储吗」或「还有进程在跑」就把它放上发起的那块屏；等满了还在、也没在问，提示无响应
    public func close(_ window: WindowInfo, from id: ScreenID) {
        guard !watcher.isWatching(.close(window.key)) else { return }
        desks[id]?.setNotice(nil)
        state.closing.insert(window.key)
        lane.run {
            if let desk = self.holder(of: window.key) {
                guard await desk.returnToOriginal(restoringState: false) else {
                    Log.warn("\(window.label) 放不回去，先不关")
                    self.state.closing.remove(window.key)
                    self.desks[id]?.setNotice(.windowUnresponsive(app: window.app))
                    return
                }
                await desk.matchWidth()
            }
            if await self.windows.look(window.key)?.fullScreen == true { await self.windows.setFullScreen(window.key, false) }
            // 飞书、微信点关闭只是把窗口藏起来：在屏上的窗口按完关闭不在屏上了，也算关上
            let wasShown = await self.windows.isShown(window.key)
            guard await self.windows.close(window.key) else {
                let notice = await self.env.unreachable(window)
                Log.warn("关不了 \(window.label)（\(Desk.reason(notice, gone: "已经关了"))）")
                self.state.closing.remove(window.key)
                self.desks[id]?.setNotice(notice)
                return
            }
            Log.info("关闭 \(window.label)")
            self.watchClose(window, hides: wasShown, from: id)
        }
    }

    /// 手机上点了屏上那个窗口自己的关闭按钮（手势翻译拦下来的）：和在 App 资源库里关一样，先放回原位、缩回字号再关。
    /// 直接让它关，App 会把屏上的大小和字号存下来，下次开出来还是那样（issue #14）
    public func closePlaced(window id: UInt32) {
        guard let desk = desks.values.first(where: { $0.placedWindow?.id == id }), let placed = desk.state.placed else { return }
        Log.info("手机上点了 \(placed.window.label) 的关闭按钮：先放回原位再关")
        close(placed.window, from: desk.id)
    }

    /// 打开 App（newWindowIn 给了就是给这个进程新建窗口），等它此刻在屏上、之前不在屏上的标准窗口出来，放上这块屏。
    /// 认「之前不在屏上」而不认新编号：唤回时 App 常常重新显示原来那个窗口，编号不变
    private func openWindow(of app: AppInfo, newWindowIn running: Int32?, on desk: Desk) async {
        let started = timeline.now
        guard desk.readyDisplay(for: "打开 \(app.name)") != nil else { return desk.setNotice(.screenNotReady) }
        // 点之前就在跑的那个进程（没在跑是 nil）：等的是它此刻之后才露出来的窗口
        let runningPid = if let running { running } else { await apps.pid(of: app) }
        if let runningPid, state.quitting.contains(runningPid) { return Log.info("\(app.name) 正在退出，不打开") }
        var before: Set<WindowKey> = []
        if let runningPid { before = Set(await windows.shownWindows(of: runningPid).map(\.key)) }
        let pid: Int32
        if let running {
            guard await apps.newWindow(pid: running) else {
                Log.warn("\(app.name) 菜单里没有「新建窗口」（或没响应），没法新建窗口")
                return desk.setNotice(.noNewWindow(app: app.name))
            }
            pid = running
        } else {
            guard let opened = await apps.open(app) else {
                Log.warn("打不开 \(app.name)（\(app.path ?? app.bundleID)）")
                return desk.setNotice(.openFailed(app: app.name))
            }
            pid = opened
        }
        let wait = runningPid == nil ? Self.launchWait : Self.windowWait
        switch await awaitWindow(of: pid, excluding: before, within: wait, for: desk) {
        case .appeared(let window):
            let how = running != nil ? "新建窗口" : runningPid == nil ? "启动" : "唤回"
            Log.info("\(app.name) \(how)后 \(String(format: "%.1f", timeline.now - started))s 出现 \(window.label)，放上屏（\(desk.id)）")
            desk.advance(to: .placing(window))
            await place(window, on: desk)
        case .appQuit:
            Log.warn("\(app.name) 打开后又退出了，没有窗口")
            desk.setNotice(.openFailed(app: app.name))
        case .timedOut:
            Log.warn("\(app.name) 打开了，但 \(Int(wait))s 内没有可显示的窗口")
            desk.setNotice(.noWindow(app: app.name))
        case .abandoned:
            Log.info("不要这块屏了，不再等 \(app.name) 的窗口")
        }
    }

    private enum Awaited {
        case appeared(WindowInfo)
        /// App 中途退了（启动就崩、自己退了）
        case appQuit
        case timedOut
        /// 不要这块屏了（远程结束、Snug 退出）：排在后面的撤屏不能干等
        case abandoned
    }

    private func awaitWindow(of pid: Int32, excluding known: Set<WindowKey>, within seconds: TimeInterval, for desk: Desk) async -> Awaited {
        let deadline = timeline.now + seconds
        while desk.wanted {
            if let window = await windows.shownWindows(of: pid).first(where: { !known.contains($0.key) }) { return .appeared(window) }
            guard await apps.isRunning(pid: pid) else { return .appQuit }
            guard timeline.now < deadline else { return .timedOut }
            await timeline.sleep(Self.windowPoll)
        }
        return .abandoned
    }

    /// 盯着请它退出的 App：退完了就好；在问就放上发起的那块屏等人答，答了取消就不再盯；
    /// 等满了还没退、也没在问，提示可以强制退出，之后再低频看一阵：它自己退了，提示就撤掉
    private func watchQuit(_ app: RunningApp, from id: ScreenID) {
        watcher.watch(.quit(app.pid)) {
            defer { self.state.quitting.remove(app.pid) }
            let answer = await self.watcher.awaitAnswer(from: app.pid, within: Self.quitWait, done: { await !self.apps.isRunning(pid: app.pid) },
                                                        ask: self.asking(on: id))
            guard !Task.isCancelled else { return }
            switch answer {
            case .done:
                Log.info("\(app.app.name) 已退出")
                self.onGone?(.app(app.pid))
            case .canceled: Log.info("\(app.app.name) 没退出（对话框里点了取消）")
            case .stalled:
                Log.warn("\(app.app.name) 请它退出 \(Int(Self.quitWait))s 后还在，也没有对话框")
                let stalled = Desk.Notice.quitStalled(app: app.app.name, pid: app.pid)
                self.desks[id]?.setNotice(stalled)
                self.state.quitting.remove(app.pid)
                let until = self.timeline.now + Self.stalledFollow
                while !Task.isCancelled, self.timeline.now < until, await self.apps.isRunning(pid: app.pid) {
                    await self.timeline.sleep(Self.stalledPoll)
                }
                guard !Task.isCancelled, await !self.apps.isRunning(pid: app.pid) else { return }
                Log.info("\(app.app.name) 后来自己退出了")
                self.onGone?(.app(app.pid))
                if self.desks[id]?.state.notice == stalled { self.desks[id]?.setNotice(nil) }
            }
        }
    }

    /// 盯着请它关掉的窗口，同退出；等满了还在、也没在问，提示无响应。
    /// hides：按关闭前它在屏上，那么不在屏上了（飞书、微信关成了隐藏）也算关上
    private func watchClose(_ window: WindowInfo, hides: Bool, from id: ScreenID) {
        watcher.watch(.close(window.key)) {
            defer { self.state.closing.remove(window.key) }
            let answer = await self.watcher.awaitAnswer(from: window.key.pid, within: Self.closeWait, done: {
                guard await self.windows.exists(window.key) else { return true }
                guard hides else { return false }
                return await !self.windows.isShown(window.key)
            }, ask: self.asking(on: id))
            guard !Task.isCancelled else { return }
            switch answer {
            case .done:
                Log.info("\(window.label) 已关闭")
                self.onGone?(.window(window.key))
            case .canceled: Log.info("\(window.label) 没关（对话框里点了取消）")
            case .stalled:
                Log.warn("\(window.label) 请它关掉 \(Int(Self.closeWait))s 后还在，也没有对话框")
                self.desks[id]?.setNotice(.windowUnresponsive(app: window.app))
            }
        }
    }

    /// App 在问用户：把问的那个窗口放上发起的那块屏，在手机上就能答
    private func asking(on id: ScreenID) -> (WindowInfo) async -> Void {
        { [self] window in
            Log.info("\(window.app) 在问，把 \(window.label) 放上屏（\(id)）")
            await placeAsking(window, on: id)
        }
    }

    /// 排进队里再放，轮到它时才显示「正在打开」
    private func placeAsking(_ window: WindowInfo, on id: ScreenID) async {
        guard !Task.isCancelled else { return }
        await lane.run {
            guard let desk = self.desks[id] else { return }
            await desk.perform(.placing(window)) { await self.place(window, on: desk, zoom: false) }
        }.value
    }

    // MARK: 定期和屏幕变化

    /// 屏幕配置变了（插拔外接屏、系统改模式、Snug 自己换档、撤掉的屏真下线了）：过一会儿检查各块屏还是不是该用的那一档、
    /// 窗口还铺不铺满；撤屏没办完的接着办
    public func displaysChanged() {
        settleDisplays()
        guard desks.values.contains(where: { screens.display($0.id) != nil }) else { return }
        recheckGeneration += 1
        let generation = recheckGeneration
        pendingRecheck = Task {
            await timeline.sleep(Self.recheckDelay)
            guard generation == recheckGeneration else { return }
            lane.run {
                for desk in self.orderedDesks { await desk.recheck() }
            }
        }
    }

    /// 定期调用：各块屏上的窗口被关掉了，就回到 App 资源库（见 Desk.verify）
    public func verifyPlacement() {
        guard desks.values.contains(where: \.needsVerify) else { return }
        lane.runCoalesced("verify") {
            for desk in self.orderedDesks where desk.needsVerify { await desk.verify() }
        }
    }

    /// 远程在不在进行（会话层的结论）。远程结束后，远程中撤屏留下的永久配置要重写（settleDisplays）
    public func setRemote(_ on: Bool) {
        if screens.setRemote(on), !on { settleDisplays() }
    }

    /// 定期调用、屏幕配置一变也调用：撤屏后屏真下线了，就放回窗口、设回别的屏；远程中撤过屏的，
    /// 远程结束、屏都醒着时把别的屏此刻的模式写进永久配置。没事可做时什么都不做
    public func settleDisplays() {
        guard screens.owesSettling else { return }
        lane.runCoalesced("settle") { await self.screens.settleDisplays() }
    }

    /// 有辅助功能权限后调用：上次 Snug 没来得及放回去的窗口，按还原账一笔一笔放回去（触屏一块屏一笔，电脑屏挪过来的窗口一个一笔，
    /// 盘上同一种格式，见 SnugPaths.broughtRecord）。账在队里轮到时才读，不会拿旧的放两遍。
    /// 2.5 及以前的还原账先挪成那块手机屏的账
    public func recover() {
        lane.run {
            let records = PlacedRecords(paths: self.env.paths)
            records.migrateLegacy()
            for id in records.screens() {
                await (self.desks[id] ?? Desk(id: id, behavior: .touchScreen, env: self.env)).putBackLeftover()
            }
        }
    }

    /// 定期调用（和 verifyPlacement 同一拍）：刚在 Snug 之外没了的窗口，它的 App 换没换个新窗口（换了就接着放上来）；
    /// 留下的账的窗口回来没有（带着屏上的大小回来就还账）。没账可查时什么都不做
    public func checkReturns() {
        guard desks.values.contains(where: \.watchesReplacement) || !env.leftBehind.isEmpty,
              desks.values.allSatisfy({ $0.state.work == nil }) else { return }
        lane.runCoalesced("returns") {
            for desk in self.orderedDesks { await desk.followReplacement() }
            await self.takeBackReturned()
        }
    }

    /// 留下的账的窗口回来了（同一个 App 的窗口带着 Snug 铺成的大小出现）：还在远程、它就开在一块空着的 Snug 屏上，
    /// 接着放着（手机上关掉又重开）；否则放回原位，字号随窗口回来的一起缩回。一次只还一笔，还不成（App 没响应）下一拍再试
    private func takeBackReturned() async {
        await env.leftBehind.repayAppWideZoom()
        // 各屏还放着的、还原账上还欠着的窗口（放回时 App 卡住）归那本账还，别被别的账认走。
        // 屏撤了账还在（远程结束时 App 卡着）：按 placed/ 下的账算，不只看还在的屏
        let owed = PlacedRecords(paths: env.paths).screens().compactMap { RestoreRecord<PlacedRecord>(url: env.paths.placedRecord(for: $0)).pending()?.window }
        let skip = Set(desks.values.compactMap(\.placedWindow) + owed)
        guard let back = await env.leftBehind.nextReturn(skip: skip) else { return }
        let center = CGPoint(x: back.frame.midX, y: back.frame.midY)
        if let id = screens.screen(at: center), let desk = desks[id], desk.awaitsReturn, desk.behavior.touch {
            // 还在远程、回到了一块空着的 Snug 屏上：接着放（Desk.place 认得出这笔账，原位、字号接着用）
            await desk.placeOnItsOwn(back.window)
            return
        }
        await env.leftBehind.repay(back.owed, window: back.window, to: screens.currentFrame(back.owed.record))
    }

    /// 退出前：放回窗口、撤掉所有屏，做完才返回
    public func shutdown() async {
        wishes = []
        for desk in desks.values { desk.wanted = false }
        await lane.run { await self.reconcile() }.value
    }

    /// 等排着的动作都做完，包括还没到点的重试和盯着的退出、关窗（测试用：真实时钟下最长要等 30 秒的重试）
    func idle() async {
        var retries: Set<Task<Void, Never>>
        repeat {
            retries = Set(screens.retries)
            await pendingRecheck?.value
            for retry in retries { await retry.value }
            for watch in watcher.running { await watch.value }
            await lane.drain()
        } while Set(screens.retries) != retries || !watcher.running.isEmpty
    }

    /// 按屏幕列表的顺序
    private var orderedDesks: [Desk] {
        wishes.compactMap { desks[$0.id] } + desks.values.filter { desk in !wishes.contains { $0.id == desk.id } }
    }
}
