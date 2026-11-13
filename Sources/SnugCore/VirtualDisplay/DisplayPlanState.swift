// 显示执行器的内部状态，以及每个动作完成后怎样更新它（纯值类型，时间由调用方给）
import Foundation

/// 调用方只声明目标，执行器负责一步步收敛过去
public struct DisplayTarget: Equatable, Sendable, CustomStringConvertible {
    public var profile: DeviceProfile?
    public var keepOnlyVirtual: Bool
    public static let none = DisplayTarget(profile: nil, keepOnlyVirtual: false)

    public init(profile: DeviceProfile?, keepOnlyVirtual: Bool) {
        self.profile = profile
        self.keepOnlyVirtual = keepOnlyVirtual
    }

    public var description: String {
        guard let p = profile else { return "无" }
        return "\(p.name) \(p.sizeLabel)\(keepOnlyVirtual ? " 只留虚拟屏" : "")"
    }
}

/// 暴露给界面的未解决问题
public enum DisplayIssue: Equatable, Sendable {
    case physicalRestoreFailing([DisplayID], DisplayFailure)
    case physicalRecordDropped([DisplayID])
    case createFailed(name: String, reason: String)
    case layoutSnapshotFailed(String)
    case layoutRestoreFailed(DisplayFailure)
    case physicalDisableFailed(DisplayFailure)
    case wedged(DisplayFailure)

    public var message: String {
        switch self {
        case .physicalRestoreFailing(let ids, let f): "恢复物理屏 \(ids) 失败（\(f)），后台继续重试"
        case .physicalRecordDropped(let ids): "物理屏 \(ids) 多次恢复失败，可能已被拔掉，已不再重试"
        case .createFailed(let name, let reason): "没能为「\(name)」准备虚拟屏：\(reason)"
        case .layoutSnapshotFailed(let why): "记录屏幕布局失败，本次不建虚拟屏：\(why)"
        case .layoutRestoreFailed(let f): "还原屏幕布局失败（\(f)），可在菜单里重试"
        case .physicalDisableFailed(let f): "熄灭物理屏失败（\(f)）"
        case .wedged(let f): "屏幕设置无响应（\(f)），请注销或重启 Mac"
        }
    }
}

/// 本工具建的一块虚拟屏
public struct VirtualDisplayRecord: Equatable, Sendable {
    public let id: DisplayID
    public let profile: DeviceProfile
    public let serial: UInt32
    public let bornAt: Date
    public var isMain = false
}

public struct DisplayPlanState: Equatable, Sendable {
    struct ReleasedDisplay: Equatable, Sendable {
        let id: DisplayID
        let serial: UInt32
        let releasedAt: Date
    }

    struct RestoreRetry: Equatable, Sendable {
        var failures: Int
        var nextAttemptAt: Date
    }

    struct LayoutProgress: Equatable, Sendable {
        enum Phase: Equatable, Sendable { case modes, origins }
        var phase = Phase.modes
        var failures = 0
        var nextAttemptAt: Date?
        var gaveUp = false
    }

    var target = DisplayTarget.none
    /// 目标从某设备变成「无」的时刻，断开宽限从这里算
    var targetClearedAt: Date?
    /// 热键 / 菜单要求立刻恢复物理屏；目标变化前不再关回去
    var manualHold = false

    var current: VirtualDisplayRecord?
    /// 换设备时的旧屏，等新屏成为主屏后释放
    var retiring: [VirtualDisplayRecord] = []
    /// applySettings 失败或迟迟不上线的屏，稳定后释放
    var broken: [VirtualDisplayRecord] = []
    /// 刚释放的屏：系统真正移除是异步的，同序列号的新屏要等它下线
    var released: [ReleasedDisplay] = []
    /// 建屏失败的配置，目标规格变化前不再重试
    var failedProfile: DeviceProfile?

    var restoreRetries: [DisplayID: RestoreRetry] = [:]
    var layout = LayoutProgress()
    /// 关物理屏失败过，目标变化前不再尝试
    var disableSuppressed = false
    var wedged = false
    var shuttingDown = false
    var shutdownFinished = false
    var lastError: DisplayIssue?

    init() {}

    // MARK: 外部意图

    mutating func setTarget(_ new: DisplayTarget, now: Date) {
        guard new != target else { return }
        if new.profile == nil, target.profile != nil {
            targetClearedAt = now
            // 每次拆屏都给布局还原一轮新的重试机会
            layout = LayoutProgress()
        }
        if new.profile != nil { targetClearedAt = nil }
        if !Self.sameSpec(new.profile, failedProfile) { failedProfile = nil }
        if !Self.sameSpec(new.profile, target.profile) || new.keepOnlyVirtual != target.keepOnlyVirtual {
            disableSuppressed = false
        }
        manualHold = false
        target = new
    }

    /// 热键 / 菜单：立刻恢复物理屏，退避清零
    mutating func requestManualRestore(now: Date) {
        manualHold = true
        for id in restoreRetries.keys { restoreRetries[id]?.nextAttemptAt = now }
    }

    mutating func retryLayout() {
        layout = LayoutProgress()
        if case .layoutRestoreFailed = lastError { lastError = nil }
    }

    // MARK: 动作结果

    mutating func recordRestore(_ result: PhysicalRestoreResult, now: Date) {
        for id in result.restored { restoreRetries[id] = nil }
        if let failure = result.failure {
            for id in result.failed {
                let failures = (restoreRetries[id]?.failures ?? 0) + 1
                restoreRetries[id] = RestoreRetry(failures: failures,
                                                  nextAttemptAt: now.addingTimeInterval(DisplayTiming.restoreDelay(afterFailures: failures)))
            }
            note(failure)
            if !wedged { lastError = .physicalRestoreFailing(result.failed, failure) }
        } else if case .physicalRestoreFailing = lastError, restoreRetries.isEmpty {
            lastError = nil
        }
    }

    mutating func recordDropped(_ ids: [DisplayID]) {
        for id in ids { restoreRetries[id] = nil }
        lastError = .physicalRecordDropped(ids)
    }

    /// 从记录里删不掉：再给一次慢速重试的机会，免得每一拍都去删
    mutating func recordDropFailed(_ ids: [DisplayID], now: Date) {
        for id in ids {
            restoreRetries[id] = RestoreRetry(failures: DisplayTiming.maxRestoreFailures - 1,
                                              nextAttemptAt: now.addingTimeInterval(DisplayTiming.restoreBackoff.last ?? 30))
        }
    }

    mutating func recordReleased(_ ids: [DisplayID], now: Date) {
        let all = [current].compactMap { $0 } + retiring + broken
        for record in all where ids.contains(record.id) {
            released.append(ReleasedDisplay(id: record.id, serial: record.serial, releasedAt: now))
        }
        released.removeAll { now.timeIntervalSince($0.releasedAt) > DisplayTiming.sameSerialWait }
        if let c = current, ids.contains(c.id) { current = nil }
        retiring.removeAll { ids.contains($0.id) }
        broken.removeAll { ids.contains($0.id) }
    }

    /// 5s 没上线：按建屏失败处理，转入 broken（稳定后释放），记下失败的配置
    mutating func recordAbandoned(_ id: DisplayID) {
        guard let c = current, c.id == id else { return }
        current = nil
        broken.append(c)
        failedProfile = c.profile
        lastError = .createFailed(name: c.profile.name, reason: "虚拟屏 \(Int(DisplayTiming.onlineTimeout)) 秒内没有上线")
    }

    /// A→B→A：旧屏还在 retiring 里，直接拿回来用
    mutating func recordRevived(_ id: DisplayID) {
        guard let i = retiring.firstIndex(where: { $0.id == id }) else { return }
        var revived = retiring.remove(at: i)
        revived.isMain = false
        if let c = current { retiring.append(c) }
        current = revived
    }

    mutating func recordSnapshotFailed(_ profile: DeviceProfile, _ why: String) {
        failedProfile = profile
        lastError = .layoutSnapshotFailed(why)
    }

    mutating func recordCreated(_ result: VirtualCreateResult, _ request: VirtualDisplayRequest, now: Date) {
        if let old = current { retiring.append(old) }
        current = nil
        switch result {
        case .created(let id):
            current = VirtualDisplayRecord(id: id, profile: request.profile, serial: request.serial, bornAt: now)
            if case .createFailed = lastError { lastError = nil }
            if case .layoutSnapshotFailed = lastError { lastError = nil }
        case .applyFailed(let id):
            broken.append(VirtualDisplayRecord(id: id, profile: request.profile, serial: request.serial, bornAt: now))
            failedProfile = request.profile
            lastError = .createFailed(name: request.profile.name, reason: "applySettings 失败")
        case .failed(let why):
            failedProfile = request.profile
            lastError = .createFailed(name: request.profile.name, reason: why)
        }
    }

    /// 设主屏失败也不重试（避免来回折腾），系统会自己挑一块主屏
    mutating func recordSetMain(_ id: DisplayID, _ outcome: TransactionOutcome) {
        if current?.id == id { current?.isMain = true }
        if let f = outcome.failure { note(f) }
    }

    mutating func recordDisable(_ outcome: TransactionOutcome) {
        guard let f = outcome.failure else { return }
        disableSuppressed = true
        note(f)
        if !wedged { lastError = .physicalDisableFailed(f) }
    }

    mutating func recordModes(_ outcome: TransactionOutcome) {
        // 模式失败不挡原点：退化成只还原原点
        if let f = outcome.failure { note(f) }
        layout.phase = .origins
    }

    mutating func recordOrigins(_ outcome: TransactionOutcome, now: Date) {
        guard let f = outcome.failure else {
            layout = LayoutProgress()
            if case .layoutRestoreFailed = lastError { lastError = nil }
            return
        }
        note(f)
        layout.phase = .modes
        layout.failures += 1
        let delays = DisplayTiming.layoutRetryDelays
        if layout.failures > delays.count {
            layout.gaveUp = true
        } else {
            layout.nextAttemptAt = now.addingTimeInterval(delays[layout.failures - 1])
        }
        if !wedged { lastError = .layoutRestoreFailed(f) }
    }

    /// 事务超时 / 无法完成：WindowServer 显示配置已卡死，之后只做恢复物理屏
    private mutating func note(_ failure: DisplayFailure) {
        guard failure.isWedge, !wedged else { return }
        wedged = true
        lastError = .wedged(failure)
    }

    static func sameSpec(_ a: DeviceProfile?, _ b: DeviceProfile?) -> Bool {
        guard let a, let b else { return a == nil && b == nil }
        return a.hasSameDisplaySpec(as: b)
    }
}
