// 屏幕模块，单一数据源：此刻有哪几块 Snug 屏、各是什么状态、什么比例、在哪一档，只有它知道，也只有它能改。
// 不认手机、平板、电脑，不认横竖：只认身份和宽 × 高（ScreenWish 给的）。
// 屏幕组合的每次变化都收在这里：WindowServer 在拓扑变化上很脆弱，屏建好太快就释放会卡死，热插拔还没处理完又建屏会崩。
// 一批增删（apply）前后只记一次周围的样子、只善后一次：macOS 一换屏幕组合，就把别的窗口挪来挪去、
// 把别的屏拨回它给这组屏幕记的模式（issue #13），换完按换之前的样子放回，Snug 的屏来去，别的都照旧。
// 设为主屏（docs/how-it-works.md「设为主屏」）也是拓扑变化，同样收在这里：建好、善后之后设主屏，原主屏上的窗口跟着搬过去（V11）；
// 撤之前先设回（releaseMain，在 DeskSet 清场之前），窗口随之回到原主屏。改之前在内存里记下原来的排布；
// Snug 崩了，它的屏随进程消失，macOS 按剩下这组屏记的排布自己摆回（11-17 实测），用不着落盘的账。
// 动作由调用方排进同一条队（DeskSet 的 SerialLane），加屏失败的重试也排进这条队
import CoreGraphics
import Foundation

@MainActor
public final class ScreenSet {
    public enum State: Equatable, Sendable {
        case off
        case preparing
        case ready(DisplayID)
        /// 加屏失败（详情在日志里）。按 retryDelays 自动重试，用完就停在这里，直到不要了再要
        case failed

        public var display: DisplayID? {
            if case .ready(let id) = self { id } else { nil }
        }
    }

    /// 屏幕组合变了（或刚设回别的屏的模式）等这么久，系统挪完窗口再放回
    static let topologySettle: TimeInterval = 1
    /// 加屏失败后隔多久重试；这几次都不成就不再试，直到不要了再要
    static let retryDelays: [TimeInterval] = [5, 15, 30]

    /// 要的每块屏此刻的状态；不要的不在里面
    public private(set) var states: [ScreenID: State] = [:] {
        didSet { if states != oldValue { onChange?() } }
    }
    public var onChange: (() -> Void)?
    /// 即将加屏、撤屏，或把被拨动的别的屏设回去：会话层据此暂缓断开判定（屏幕一变，UU 的信号会抖一下）
    public var onTopologyChange: (() -> Void)?
    /// 放在 Snug 屏上的窗口：加屏、撤屏后放回别的窗口时跳过它们（由 DeskSet 给，ScreenSet 不认 Desk）
    var placedWindows: () -> Set<WindowKey> = { [] }

    private let displays: any VirtualDisplays
    private let windows: any WindowControl
    private let arrangement: any DisplayArrangement
    private let timeline: any Timeline
    private let lane: SerialLane
    /// 设主屏之前各屏的原点（按 Snug 的屏出现前的主屏换算）。设回成功才清；摆不回去时留着，再设主屏时还用这份最早的
    private var savedOrigins: [DisplayID: CGPoint]?
    /// 此刻被设成主屏的那块 Snug 屏
    private(set) var mainScreen: ScreenID?
    /// Snug 的屏出现之前的主屏（建第一块屏前记下）：设主屏记账时按它算原来的排布
    private var homeMain: DisplayID?
    /// 设成主屏的那块屏，和设主屏后全局坐标整体平移了多少：主屏的原点总在 (0,0)，设主屏时别的屏连同窗口一起平移，
    /// 此刻的坐标加上它就是没设主屏时的坐标（见 homeFrame）。设回、或那块屏撤掉（系统随之摆回）时归零
    private var claimed: (display: DisplayID, shift: CGVector)?
    /// 要的屏，按屏幕列表的顺序（建屏按这个顺序，UU 也按建屏顺序列出）
    private var wishes: [ScreenWish] = []
    private var live: [ScreenID: (display: DisplayID, bornAt: TimeInterval)] = [:]
    private var failures: [ScreenID: Int] = [:]
    private var pendingRetries: [ScreenID: Task<Void, Never>] = [:]
    /// 撤掉了、还没真正下线的屏：下线那一刻 macOS 才挪窗口、拨别的屏。显示器睡着（Mac 锁屏）时释放的虚拟屏
    /// 要等唤醒才下线（实测，可能是几小时后），等它们都真下线了再按撤屏前的样子放回（settleDisplays）
    private var retiring: Retiring?
    private var mirrorDisplays: Set<DisplayID> = []
    private var desktopBeforeMirroring: Surroundings?
    private var pendingReturns: [DisplayID: (window: WindowKey, restore: () async -> Void)] = [:]

    func returnAfterRetirement(_ window: WindowKey, from display: DisplayID, restore: @escaping () async -> Void) {
        pendingReturns[display] = (window, restore)
    }

    func isWaitingToReturn(_ window: WindowKey) -> Bool {
        pendingReturns.values.contains { $0.window == window }
    }

    func wasOnDesktopBeforeMirroring(_ window: WindowKey) -> Bool {
        desktopBeforeMirroring?.windows[window] != nil
    }

    private func finishReturns() async {
        for id in pendingReturns.keys.sorted() where !displays.isOnline(id) {
            if let pending = pendingReturns.removeValue(forKey: id) { await pending.restore() }
        }
    }
    /// 远程在不在进行（会话层的结论，含断开后等重连的那段）：这期间别的屏可能处在远程用的临时模式
    private var remote = false
    /// 远程中撤过屏：那时别的屏可能正处在远程用的临时模式，系统套用时连永久配置一起写了。
    /// 远程结束（UU 已经还原）、Snug 的屏都不在、屏都醒着时，把别的屏此刻的模式写进永久配置
    private var persistOwed = false

    init(displays: any VirtualDisplays, windows: any WindowControl, arrangement: any DisplayArrangement, timeline: any Timeline,
         lane: SerialLane) {
        self.displays = displays
        self.windows = windows
        self.arrangement = arrangement
        self.timeline = timeline
        self.lane = lane
    }

    // MARK: 差量

    /// 对照现状做差量（在队里调用）：新的建出来，没了的撤掉，比例变了的在线换（同一身份），其余不碰。
    /// 交回这次换了比例的屏和换成了没有。设回主屏由调用方在清场前做（releaseMain）
    func apply(_ wishes: [ScreenWish]) async -> [ScreenID: Bool] {
        let wanted = Set(wishes.map(\.id))
        for id in pendingRetries.keys where !wanted.contains(id) { cancelRetry(id) }
        self.wishes = wishes
        await reconcile()
        var reshaped: [ScreenID: Bool] = [:]
        for wish in wishes {
            guard let display = live[wish.id]?.display, let now = displays.fit(display), now != wish.fit else { continue }
            reshaped[wish.id] = await reshape(display, to: wish.fit)
        }
        await claimMain()
        return reshaped
    }

    /// 撤掉不要的、建出要了还没有的；失败的按 retryDelays 排队重试。
    /// 失败的那块只在轮到它的重试（retrying）时再建：别的设置改了也走这里，当场再建会把重试次数提前耗掉，用完了还每次都建
    private func reconcile(retrying: ScreenID? = nil) async {
        let wanted = Set(wishes.map(\.id))
        let retire = live.keys.filter { !wanted.contains($0) }.sorted { $0.rawValue < $1.rawValue }
        let create = wishes.filter { live[$0.id] == nil && (states[$0.id] != .failed || $0.id == retrying) }
        for id in states.keys where !wanted.contains(id) && live[id] == nil { states[id] = nil }
        guard !retire.isEmpty || !create.isEmpty else { return }
        for wish in create { states[wish.id] = .preparing }

        let change = create.isEmpty ? "撤屏" : retire.isEmpty ? "加屏" : "加撤屏"
        if let old = retiring, !create.isEmpty {
            retiring = nil
            Log.warn("撤掉的屏 \(old.displays.map { "#\($0)" }.joined(separator: "、")) 还没下线就又要加屏，不再等：它们下线时被挪动的窗口、被拨动的屏不会按撤屏前的样子放回")
        }
        if live.isEmpty, !create.isEmpty { homeMain = arrangement.origins().first { $0.value == .zero }?.key }
        var before = await surroundings(before: change)
        let beforeAdding = before
        onTopologyChange?()

        var offline = true
        var gone: [DisplayID] = []
        for id in retire {
            guard let (display, bornAt) = live[id] else { continue }
            let age = timeline.now - bornAt
            if age < ScreenSpec.minimumLifetime { await timeline.sleep(ScreenSpec.minimumLifetime - age) }
            // 原本就在这块屏上的窗口交给系统安置：那块屏已经没了，放回原处只会落到屏幕外
            if let bounds = displays.bounds(display) {
                before.windows = before.windows.filter { key, frame in
                    wasOnDesktopBeforeMirroring(key) || !bounds.contains(CGPoint(x: frame.midX, y: frame.midY))
                }
            }
            if await !displays.retire(display) { offline = false }
            // 设回没摆成的那块主屏撤掉了：系统按剩下这组屏记的排布摆回，坐标回到没设主屏时的样子
            if claimed?.display == display { claimed = nil }
            live[id] = nil
            states[id] = nil
            gone.append(display)
            mirrorDisplays.remove(display)
            Log.info("已撤掉屏 #\(display)（\(id)）")
        }

        let desktop = mirrorDisplays.isEmpty ? desktopBeforeMirroring : nil
        if mirrorDisplays.isEmpty { desktopBeforeMirroring = nil }
        var created: [ScreenID: DisplayID] = [:]
        for wish in create {
            do {
                let display = try await displays.create(wish.spec, wish.fit)
                live[wish.id] = (display, timeline.now)
                created[wish.id] = display
                if displays.isMirrored(display) {
                    mirrorDisplays.insert(display)
                    if desktopBeforeMirroring == nil { desktopBeforeMirroring = desktop ?? beforeAdding }
                    Log.info("屏 #\(display) 加入了镜像组，保留镜像前的桌面位置和尺寸")
                }
                failures[wish.id] = nil
                Log.info("「\(wish.spec.name)」#\(display) 已建好（\(displays.width(display).map { "\($0) 宽" } ?? "不是 2 倍")）")
            } catch {
                states[wish.id] = .failed
                Log.error("加「\(wish.spec.name)」失败：\(error)")
                scheduleRetry(wish.id)
            }
        }

        // 远程结束后撤屏（UU 已经还原），撤屏前的样子就是用户自己的设置：系统套用旧模式时也写进了永久配置，
        // 只设回本次登录，磁盘上那组屏幕记的还是旧模式（实测），所以连永久配置一起写回。
        // 加屏、远程中撤屏，之前可能是远程用的临时模式：只设回本次登录，远程结束后再写永久配置
        if !retire.isEmpty, remote { persistOwed = true }
        let batch = Retiring(displays: gone, before: before, desktop: desktop, permanently: create.isEmpty && !remote)
        let pending = retiring.map { $0.joined(batch) } ?? batch
        retiring = nil
        if offline, !pending.displays.contains(where: displays.isOnline) {
            await settle(pending, after: change)
        } else {
            retiring = pending
            Log.info("撤掉的屏还没下线（显示器睡着时要等唤醒），下线后再放回窗口、设回别的屏")
        }
        for (id, display) in created { states[id] = .ready(display) }
    }

    /// 加屏失败后过一会儿再试：手机上没有任何入口能重来，不重试就要等这次远程结束
    private func scheduleRetry(_ id: ScreenID) {
        pendingRetries[id]?.cancel()
        pendingRetries[id] = nil
        let count = failures[id] ?? 0
        guard count < Self.retryDelays.count else {
            Log.error("加屏（\(id)）连续失败 \(count + 1) 次，这次远程不再重试")
            return
        }
        let delay = Self.retryDelays[count]
        failures[id] = count + 1
        Log.info("\(Int(delay)) 秒后重试加屏（\(id)，第 \(count + 1) 次重试）")
        pendingRetries[id] = Task {
            await timeline.sleep(delay)
            guard !Task.isCancelled else { return }
            await lane.run {
                await self.reconcile(retrying: id)
                await self.claimMain()
            }.value
        }
    }

    private func cancelRetry(_ id: ScreenID) {
        pendingRetries.removeValue(forKey: id)?.cancel()
        failures[id] = nil
    }

    /// 还没到点的重试（测试等它们做完）
    var retries: [Task<Void, Never>] { Array(pendingRetries.values) }

    /// 换比例：屏在线换成新档位（屏不掉线、编号不变，UU 里选中的屏不丢）。换不成屏还是原来的档位，下次建屏按新的建
    private func reshape(_ display: DisplayID, to fit: ScreenFit) async -> Bool {
        guard await displays.reshape(display, to: fit) else {
            Log.warn("屏 #\(display) 没能换成新比例（\(fit)），下次加屏时按新的建")
            return false
        }
        return true
    }

    // MARK: 善后

    /// Snug 的屏以外的一切：窗口在哪、别的屏是什么模式。macOS 一换屏幕组合就会动它们：把窗口挪来挪去，
    /// 把别的屏拨回它给新的这组屏幕记的模式（远程期间主屏被临时改成 30Hz，撤屏时又被拨回 30Hz，issue #13）
    private struct Surroundings {
        var windows: [WindowKey: CGRect]
        var others: [OtherDisplay]
        /// 当时在的 Snug 屏在哪：系统挪屏让地方时不分是不是 Snug 的，留着的那几块上的窗口也要跟着平移
        var snug: [DisplayID: CGRect]
    }

    private struct Retiring {
        var displays: [DisplayID]
        var before: Surroundings
        var desktop: Surroundings?
        var permanently: Bool

        /// 上一批还没下线又撤了一批：一起等，都下线了按第一批之前的样子放回（屏没下线前系统不挪窗口，显示器睡着时也没人动）；
        /// 后一批撤掉的屏上的窗口不在后一份里，交给系统
        func joined(_ later: Retiring) -> Retiring {
            var before = before
            before.windows = before.windows.filter { later.before.windows[$0.key] != nil }
            return Retiring(displays: displays + later.displays, before: before, desktop: desktop ?? later.desktop, permanently: permanently && later.permanently)
        }
    }

    /// 记下来，别的屏的模式也写进日志：出了问题能分清是换屏幕组合时被拨动的，还是之前就是这样
    private func surroundings(before change: String) async -> Surroundings {
        let others = displays.otherDisplays()
        Log.info("\(change)前别的屏：\(others.isEmpty ? "没有" : others.map { "\($0.name) \($0.mode)" }.joined(separator: "、"))")
        let snug = Dictionary(uniqueKeysWithValues: live.values.compactMap { v in displays.bounds(v.display).map { (v.display, $0) } })
        return Surroundings(windows: await windows.snapshot(), others: others, snug: snug)
    }

    /// 屏幕组合换完（新屏上线、旧屏下线）后放回：先设回被拨动的屏（模式连分辨率一起变时会再挪窗口），
    /// 等系统挪完，再放回被挪动的窗口。这期间拔掉、新接上的屏不碰
    private func settle(_ batch: Retiring, after change: String) async {
        let before = batch.before
        await timeline.sleep(Self.topologySettle)
        let now = Dictionary(displays.otherDisplays().map { ($0.id, $0.mode) }, uniquingKeysWith: { first, _ in first })
        let homeModes = Dictionary(uniqueKeysWithValues: (batch.desktop?.others ?? []).map { ($0.id, $0) })
        let expected = before.others.map { homeModes[$0.id] ?? $0 }
        let drifted = expected.compactMap { was in now[was.id].flatMap { $0.isSame(as: was.mode) ? nil : (was, $0) } }
        if !drifted.isEmpty {
            let detail = drifted.map { was, now in "\(was.name) \(was.mode) → \(now)" }.joined(separator: "、")
            Log.info("\(change)时 macOS 把别的屏拨成了它给这组屏幕记的模式（\(detail)），设回\(change)前的样子")
            onTopologyChange?()
            for (was, _) in drifted { await displays.setMode(was.id, was.mode, permanently: batch.permanently) }
            await timeline.sleep(Self.topologySettle)
        }
        var was = Dictionary(before.others.map { ($0.id, $0.bounds) }, uniquingKeysWith: { first, _ in first })
        var at = Dictionary(displays.otherDisplays().map { ($0.id, $0.bounds) }, uniquingKeysWith: { first, _ in first })
        for (display, bounds) in before.snug {
            was[display] = bounds
            at[display] = displays.bounds(display)
        }
        if mirrorDisplays.isEmpty {
            var targets = Self.following(before.windows, from: was, to: at)
            if let desktop = batch.desktop {
                let originalScreens = Dictionary(uniqueKeysWithValues: desktop.others.map { ($0.id, $0.bounds) })
                let known = desktop.windows.filter { targets[$0.key] != nil }
                targets.merge(Self.following(known, from: originalScreens, to: at)) { _, original in original }
            }
            await windows.restore(targets, except: placedWindows().union(pendingReturns.values.map(\.window)))
        }
        await finishReturns()
    }

    /// 窗口该在的位置：所在的屏被 macOS 挪了（Snug 的屏多了，它会把外接屏挪开让地方，撤屏后再挪回来），
    /// 屏上的窗口是跟着屏走的，记下的位置也按屏挪过的距离平移，不然放回去反倒把它们推偏
    static func following(_ windows: [WindowKey: CGRect], from before: [DisplayID: CGRect], to now: [DisplayID: CGRect]) -> [WindowKey: CGRect] {
        let moved: [(was: CGRect, by: CGVector)] = before.compactMap { id, was in
            guard let now = now[id], now.origin != was.origin else { return nil }
            return (was, CGVector(dx: now.minX - was.minX, dy: now.minY - was.minY))
        }
        guard !moved.isEmpty else { return windows }
        return windows.mapValues { frame in
            guard let shift = moved.first(where: { $0.was.contains(CGPoint(x: frame.midX, y: frame.midY)) })?.by else { return frame }
            return frame.offsetBy(dx: shift.dx, dy: shift.dy)
        }
    }

    /// 远程在不在进行（会话层的结论）。远程结束后，远程中撤屏留下的永久配置要重写（settleDisplays）
    func setRemote(_ on: Bool) -> Bool {
        guard on != remote else { return false }
        remote = on
        return true
    }

    /// 有没有善后要做：撤掉的屏还没下线，或远程中撤过屏、永久配置要重写
    var owesSettling: Bool { retiring != nil || persistOwed || !pendingReturns.isEmpty }

    /// 撤掉的屏真下线了，就放回窗口、设回别的屏；远程中撤过屏的，远程结束、屏都醒着时把别的屏此刻的模式写进永久配置
    func settleDisplays() async {
        if let r = retiring {
            guard !r.displays.contains(where: displays.isOnline) else { return }
            retiring = nil
            Log.info("撤掉的屏 \(r.displays.map { "#\($0)" }.joined(separator: "、")) 下线了")
            await settle(r, after: "撤屏")
        }
        await finishReturns()
        guard persistOwed, !remote, live.isEmpty else { return }
        let others = displays.otherDisplays()
        guard !others.contains(where: \.asleep) else { return }
        persistOwed = false
        Log.info("远程中撤过屏，远程结束后把别的屏此刻的模式写进永久配置：\(others.map { "\($0.name) \($0.mode)" }.joined(separator: "、"))")
        for other in others { await displays.setMode(other.id, other.mode, permanently: true) }
    }

    // MARK: 主屏

    /// 设主屏的那块要撤、或不再要它当主屏：先设回原来的主屏（在 DeskSet 清场之前调，跟过去的窗口随之回到原主屏，
    /// 剩下的才要清场）
    func releaseMain(keeping wishes: [ScreenWish]) async {
        guard let id = mainScreen, !wishes.contains(where: { $0.id == id && $0.main }) else { return }
        mainScreen = nil
        await restoreArrangement(because: "「\(id)」不再当主屏")
    }

    /// 要设为主屏的那块建好了、还不是主屏：记下各屏的原点，再设。原主屏上的窗口跟着主屏搬过去（V11），不放回
    private func claimMain() async {
        guard mainScreen == nil, let wish = wishes.first(where: \.main), let display = live[wish.id]?.display else { return }
        var before = arrangement.origins()
        // 系统按这组屏幕记的排布已经把某块 Snug 屏设成了主屏（上次设了主屏没设回就退出了，同一次登录里再建这几块屏，11-17 实测）：
        // 按 Snug 的屏出现前的主屏换算原来的排布，不然不再当主屏时摆回的还是这个样子
        if let home = homeMain, let shift = before[home], shift != .zero {
            before = before.mapValues { CGPoint(x: $0.x - shift.x, y: $0.y - shift.y) }
        }
        // 上次没摆回去的那份留着：最早的那份才是用户自己的排布
        let fresh = savedOrigins == nil
        if fresh { savedOrigins = before }
        onTopologyChange?()
        guard await arrangement.makeMain(display) else {
            Log.error("「\(wish.spec.name)」#\(display) 设成主屏失败")
            if fresh { savedOrigins = nil }
            return
        }
        mainScreen = wish.id
        let origin = before[display] ?? .zero
        claimed = (display, CGVector(dx: origin.x, dy: origin.y))
        Log.info("「\(wish.spec.name)」#\(display) 设成主屏（原来的原点：\(Self.describe(savedOrigins ?? before))）")
        await timeline.sleep(Self.topologySettle)
    }

    private func restoreArrangement(because reason: String) async {
        guard let saved = savedOrigins else { return }
        onTopologyChange?()
        if await arrangement.restore(saved) {
            Log.info("\(reason)，排布摆回设主屏之前（\(Self.describe(saved))）")
            savedOrigins = nil
            claimed = nil
        } else {
            // 留着：再设主屏时还用这份最早的；屏撤掉时 macOS 按这组屏幕记的排布摆回
            Log.error("\(reason)，排布没能摆回去（\(Self.describe(saved))），屏撤掉时系统会按这组屏幕记的排布摆回")
        }
        await timeline.sleep(Self.topologySettle)
    }

    private static func describe(_ origins: [DisplayID: CGPoint]) -> String {
        origins.sorted { $0.key < $1.key }.map { "#\($0.key) (\(Int($0.value.x)),\(Int($0.value.y)))" }.joined(separator: "、")
    }

    // MARK: 查询、换档

    /// 就绪的屏
    public func display(_ id: ScreenID) -> DisplayID? { states[id]?.display }

    /// 屏上此刻的比例：选档只能在屏上登记的档位里选。换比例还没轮到、或者没换成时，它和要的不一样
    func fit(_ id: ScreenID) -> ScreenFit? {
        guard let wish = wishes.first(where: { $0.id == id }) else { return nil }
        return display(id).flatMap(displays.fit) ?? wish.fit
    }

    /// 此刻是哪一档；不是 2 倍、或屏不在返回 nil
    func width(_ id: ScreenID) -> Int? { display(id).flatMap(displays.width) }

    func setWidth(_ id: ScreenID, _ width: Int) async {
        guard let display = display(id), displays.width(display) != width else { return }
        await displays.setWidth(display, width)
    }

    func bounds(_ id: ScreenID) -> CGRect? { display(id).flatMap(displays.bounds) }

    func windowArea(_ id: ScreenID, withHomeBar: Bool) -> CGRect? {
        display(id).flatMap { displays.windowArea($0, withHomeBar: withHomeBar) }
    }

    func mainArea() -> CGRect? { displays.mainArea() }

    /// 窗口原位按没设主屏时的坐标记：设回、撤屏后放回都准；Snug 崩溃后系统已经摆回，账也照样对得上。
    /// 设了主屏时 macOS 在原主屏和新主屏之间整体互换窗口（V11、11-18 真机实测）：设主屏时原主屏上的窗口搬到新主屏同一处，
    /// 还原排布时新主屏上的窗口搬回原主屏，原主屏上的反倒被换到 Snug 的屏上。所以新主屏上的窗口，没设主屏时就在原主屏同一处；
    /// 别的屏上的窗口跟着自己的屏整体平移
    func homeFrame(_ frame: CGRect) -> CGRect {
        guard let claimed else { return frame }
        if let main = claimedBounds, main.contains(CGPoint(x: frame.midX, y: frame.midY)) {
            return frame.offsetBy(dx: -main.minX, dy: -main.minY)
        }
        return frame.offsetBy(dx: claimed.shift.dx, dy: claimed.shift.dy)
    }

    func savedDesktopFrame(for window: WindowKey) -> (CGRect, DisplayAnchor?)? {
        guard let desktop = desktopBeforeMirroring, let frame = desktop.windows[window] else { return nil }
        return (frame, DisplayAnchor(frame: frame, displays: desktop.others))
    }

    func displayAnchor(for frame: CGRect) -> DisplayAnchor? {
        guard claimed == nil else { return nil }
        return DisplayAnchor(frame: frame, displays: displays.otherDisplays())
    }

    func currentFrame(_ record: PlacedRecord) -> CGRect {
        guard claimed == nil, let anchor = record.originalDisplay else { return currentFrame(record.original) }
        if let screen = displays.otherDisplays().first(where: { $0.id == anchor.id }) {
            return anchor.resolve(record.original, on: screen.bounds)
        }
        return mainArea()?.centered(record.original.size) ?? record.original
    }

    /// 按原位账放回时，换成此刻的坐标（homeFrame 反过来）：原位在原主屏上的放到新主屏同一处，还原排布时系统把它带回原主屏
    func currentFrame(_ home: CGRect) -> CGRect {
        guard let claimed else { return home }
        if let main = claimedBounds, let size = homeMainSize,
           CGRect(origin: .zero, size: size).contains(CGPoint(x: home.midX, y: home.midY)) {
            return home.offsetBy(dx: main.minX, dy: main.minY)
        }
        return home.offsetBy(dx: -claimed.shift.dx, dy: -claimed.shift.dy)
    }

    /// 设了主屏时，这个点在不在设成主屏的那块屏上：在上面的窗口还原排布时会被系统搬回原主屏，原位不按落在 Snug 屏上处理
    func onClaimedScreen(_ point: CGPoint) -> Bool {
        claimedBounds?.contains(point) == true
    }

    /// 设成主屏的那块屏此刻的范围（真机上原点就是 0,0）
    private var claimedBounds: CGRect? { claimed.flatMap { displays.bounds($0.display) } }

    /// 原来那块主屏的大小：它在没设主屏时的坐标里原点是 0,0（找不到就按别的屏整体平移算）
    private var homeMainSize: CGSize? {
        guard let home = homeMain else { return nil }
        return displays.otherDisplays().first(where: { $0.id == home })?.bounds.size
    }

    /// 原来那块主屏此刻的范围：设了主屏时，此刻的主屏是 Snug 的屏，原位不能落在它上面
    func homeMainArea() -> CGRect? {
        guard claimed != nil, let home = homeMain, let bounds = displays.otherDisplays().first(where: { $0.id == home })?.bounds else {
            return mainArea()
        }
        return bounds
    }

    /// 这个点落在哪块 Snug 屏上（就绪的）
    func screen(at point: CGPoint) -> ScreenID? {
        states.keys.first { bounds($0)?.contains(point) == true }
    }
}

