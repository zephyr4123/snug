// 显示执行器的决策：纯函数，(状态, 观测) → 下一步。一次只给一个动作，执行器做完、等稳定后再来问。
// 优先级从高到低：恢复物理屏 → 保护态 → 释放坏屏 → 拆屏（目标为无）/ 建屏（目标为某设备）
import Foundation

public struct DisplayObservation: Equatable, Sendable {
    public var now: Date
    public var online: [OnlineDisplay]
    /// 磁盘上记录的待恢复物理屏
    public var disabledPhysical: [DisplayID]
    public var hasLayoutSnapshot: Bool

    public init(now: Date, online: [OnlineDisplay], disabledPhysical: [DisplayID], hasLayoutSnapshot: Bool) {
        self.now = now
        self.online = online
        self.disabledPhysical = disabledPhysical
        self.hasLayoutSnapshot = hasLayoutSnapshot
    }

    func isOnline(_ id: DisplayID) -> Bool { online.contains { $0.id == id } }
}

public enum DisplayAction: Equatable, Sendable {
    case restorePhysical([DisplayID])
    /// 连续失败太多次，从记录里丢弃（不改拓扑）
    case dropPhysical([DisplayID])
    case releaseBroken([DisplayID])
    /// 迟迟不上线：转入 broken（不改拓扑）
    case abandonVirtual(DisplayID)
    /// 把 retiring 里同规格的屏拿回来用（不改拓扑）
    case reviveRetiring(DisplayID)
    /// 建屏前采集布局快照（不改拓扑）
    case captureLayout(DeviceProfile)
    case createVirtual(VirtualDisplayRequest)
    case setMain(DisplayID)
    case releaseVirtual([DisplayID])
    case disablePhysical([DisplayID])
    case restoreModes
    case restoreOrigins
    case finishShutdown
}

public enum DisplayStep: Equatable, Sendable {
    case act(DisplayAction)
    /// 过这么久再来问（期间没有动作，外部 setTarget 可以随时插进来）
    case wait(TimeInterval)
    case idle
}

public enum DisplayPlanner {
    public static func next(_ s: DisplayPlanState, _ o: DisplayObservation) -> DisplayStep {
        var wake = Wake(now: o.now)
        if s.shutdownFinished { return .idle }

        if physicalShouldBeOn(s, o), !o.disabledPhysical.isEmpty, let step = restoreStep(s, o, &wake) {
            return step
        }
        if s.wedged {
            return s.shuttingDown ? .act(.finishShutdown) : wake.step
        }
        if !s.broken.isEmpty {
            return releaseStep(s.broken, o, &wake, as: DisplayAction.releaseBroken) ?? wake.step
        }
        if s.shuttingDown || s.target.profile == nil {
            return teardownStep(s, o, &wake)
        }
        return targetStep(s, o, &wake)
    }

    // MARK: 物理屏

    /// 物理屏该亮着的情况。最后一条兜底：没有任何一块在线的虚拟屏可用，绝不让物理屏关着（修 B7）
    static func physicalShouldBeOn(_ s: DisplayPlanState, _ o: DisplayObservation) -> Bool {
        if s.wedged || s.shuttingDown || s.manualHold || !s.target.keepOnlyVirtual || s.target.profile == nil { return true }
        let usable = ([s.current].compactMap { $0 } + s.retiring).contains { o.isOnline($0.id) }
        return !usable
    }

    /// 失败按 ID 退避，没到点的先不管，不挡后面的步骤（修 B2）
    private static func restoreStep(_ s: DisplayPlanState, _ o: DisplayObservation, _ wake: inout Wake) -> DisplayStep? {
        let ids = o.disabledPhysical
        let exhausted = ids.filter { (s.restoreRetries[$0]?.failures ?? 0) >= DisplayTiming.maxRestoreFailures }
        if !exhausted.isEmpty { return .act(.dropPhysical(exhausted)) }
        let due = ids.filter { s.restoreRetries[$0].map { $0.nextAttemptAt <= o.now } ?? true }
        guard !due.isEmpty else {
            ids.compactMap { s.restoreRetries[$0]?.nextAttemptAt }.forEach { wake.at($0) }
            return nil
        }
        // 一起恢复失败过的，之后一块一块单独试，免得被拔掉的那块拖住其余的
        if let retried = due.first(where: { (s.restoreRetries[$0]?.failures ?? 0) > 0 }) {
            return .act(.restorePhysical([retried]))
        }
        return .act(.restorePhysical(due))
    }

    // MARK: 释放

    /// 释放前必须已上线且存活 ≥2.5s；不上线的从出生算最多等 8s
    private static func releaseStep(_ records: [VirtualDisplayRecord], _ o: DisplayObservation, _ wake: inout Wake,
                                    as action: ([DisplayID]) -> DisplayAction) -> DisplayStep? {
        var readyAt = o.now
        for r in records {
            let forced = r.bornAt.addingTimeInterval(DisplayTiming.maxReleaseWait)
            if o.isOnline(r.id) {
                readyAt = max(readyAt, min(r.bornAt.addingTimeInterval(DisplayTiming.minLifetimeBeforeRelease), forced))
            } else if forced > o.now {
                // 可能马上就上线，轮询着等
                readyAt = max(readyAt, min(forced, o.now.addingTimeInterval(DisplayTiming.pollInterval)))
            }
        }
        if readyAt <= o.now { return .act(action(records.map(\.id))) }
        wake.at(readyAt)
        return nil
    }

    // MARK: 目标为无：恢复物理屏（已在最前面）→ 宽限后释放虚拟屏 → 还原布局

    private static func teardownStep(_ s: DisplayPlanState, _ o: DisplayObservation, _ wake: inout Wake) -> DisplayStep {
        let graceEnd = s.targetClearedAt.map { $0.addingTimeInterval(DisplayTiming.releaseGrace) }
        let inGrace = !s.shuttingDown && s.current != nil && graceEnd.map { o.now < $0 } == true
        let toRelease = s.retiring + (inGrace ? [] : [s.current].compactMap { $0 })
        if !toRelease.isEmpty {
            return releaseStep(toRelease, o, &wake, as: DisplayAction.releaseVirtual) ?? wake.step
        }
        if inGrace, let end = graceEnd {
            wake.at(end)
            return wake.step
        }
        var layoutWaiting = false
        if o.hasLayoutSnapshot, !s.layout.gaveUp {
            guard let next = s.layout.nextAttemptAt, next > o.now else {
                return .act(s.layout.phase == .modes ? .restoreModes : .restoreOrigins)
            }
            wake.at(next)
            layoutWaiting = true
        }
        // 退出时不等物理屏的慢速重试（交给看门狗 / snug-rescue），只等有界的布局重试
        if s.shuttingDown, !layoutWaiting { return .act(.finishShutdown) }
        return wake.step
    }

    // MARK: 目标为某设备：备好同规格的屏 → 等上线 → 设主屏 → 放掉旧屏 → 按需熄灭物理屏

    private static func targetStep(_ s: DisplayPlanState, _ o: DisplayObservation, _ wake: inout Wake) -> DisplayStep {
        guard let want = s.target.profile else { return wake.step }
        guard let cur = s.current, cur.profile.hasSameDisplaySpec(as: want) else {
            return prepareStep(want, s, o, &wake)
        }
        if !o.isOnline(cur.id) {
            if o.now.timeIntervalSince(cur.bornAt) > DisplayTiming.onlineTimeout { return .act(.abandonVirtual(cur.id)) }
            wake.at(o.now.addingTimeInterval(DisplayTiming.pollInterval))
            return wake.step
        }
        if !cur.isMain { return .act(.setMain(cur.id)) }
        if !s.retiring.isEmpty {
            return releaseStep(s.retiring, o, &wake, as: DisplayAction.releaseVirtual) ?? wake.step
        }
        if s.target.keepOnlyVirtual, !s.manualHold, !s.disableSuppressed {
            let physical = o.online.filter { !$0.isSnugVirtual }.map(\.id)
            if !physical.isEmpty { return .act(.disablePhysical(physical)) }
        }
        return wake.step
    }

    private static func prepareStep(_ want: DeviceProfile, _ s: DisplayPlanState, _ o: DisplayObservation,
                                    _ wake: inout Wake) -> DisplayStep {
        if let failed = s.failedProfile, failed.hasSameDisplaySpec(as: want) {
            // 不再重试；手上不合规格的屏都放掉，物理屏会因为没有可用虚拟屏而恢复
            let stale = s.retiring + [s.current].compactMap { $0 }
            return stale.isEmpty ? wake.step : (releaseStep(stale, o, &wake, as: DisplayAction.releaseVirtual) ?? wake.step)
        }
        if let old = s.retiring.first(where: { $0.profile.hasSameDisplaySpec(as: want) }) {
            return .act(.reviveRetiring(old.id))
        }
        let request = VirtualDisplayRequest(profile: want)
        // 同身份的旧屏还在线：等它下线（有上限），不退回随机号
        if let old = s.released.first(where: { $0.serial == request.serial && o.isOnline($0.id) }),
           o.now < old.releasedAt.addingTimeInterval(DisplayTiming.sameSerialWait) {
            wake.at(o.now.addingTimeInterval(DisplayTiming.pollInterval))
            return wake.step
        }
        // 撞号的还活着（只可能是哈希碰撞）：先放掉它
        let alive = s.retiring + [s.current].compactMap { $0 }
        if let clash = alive.first(where: { $0.serial == request.serial }) {
            return releaseStep([clash], o, &wake, as: DisplayAction.releaseVirtual) ?? wake.step
        }
        // 布局快照在会话第一次改拓扑之前采集；换设备时已有快照，不覆盖
        if !o.hasLayoutSnapshot, alive.isEmpty { return .act(.captureLayout(want)) }
        return .act(.createVirtual(request))
    }
}

/// 收集「最早什么时候该再来看一眼」
struct Wake {
    let now: Date
    private var earliest: Date?

    init(now: Date) { self.now = now }

    mutating func at(_ date: Date) {
        earliest = min(earliest ?? date, date)
    }

    var step: DisplayStep {
        guard let e = earliest else { return .idle }
        return .wait(max(0, e.timeIntervalSince(now)))
    }
}
