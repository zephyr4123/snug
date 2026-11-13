import Foundation
@testable import SnugCore

/// 假的显示驱动：在虚拟时钟上模拟物理屏、虚拟屏和两份磁盘记录，并记下每个动作发生的时刻。
/// 各动作的耗时取自 2026-11-12 19:01 的真实日志（建屏 0.29s、设主屏 0.30s、关屏 0.13s、恢复 0.12s、释放 0.09s）
@MainActor
final class FakeDisplayDriver: DisplayDriver {
    struct Call: Equatable {
        let at: Date
        let name: String
        let ids: [DisplayID]
    }

    let scheduler: VirtualScheduler
    private(set) var calls: [Call] = []

    // 系统状态
    var physical: [DisplayID] = [1, 5]
    /// disabled-displays.json（磁盘）
    var ledger: [DisplayID] = []
    /// layout.json（磁盘）
    var layoutRecord = false
    private var virtuals: [DisplayID: (serial: UInt32, onlineAt: Date?)] = [:]
    /// 已释放但系统还没移除的虚拟屏：在 until 之前仍在在线列表里
    private var lingering: [DisplayID: (serial: UInt32, until: Date)] = [:]
    private var nextID: DisplayID = 13

    // 可调的故障与耗时
    /// 虚拟屏建好后多久上线；nil 表示永远不上线
    var onlineDelay: TimeInterval? = 0.3
    var applySettingsFails = false
    /// 释放后系统还要这么久才把屏从在线列表里拿掉
    var lingerAfterRelease: TimeInterval = 0
    /// 强制从在线列表里消失的虚拟屏（模拟上线后又短暂离线）
    var forcedOffline: Set<DisplayID> = []
    /// 这些物理屏启用一直失败
    var enableFails: Set<DisplayID> = []
    var setMainError: DisplayFailure?
    var disableError: DisplayFailure?
    var restoreOriginsFailuresLeft = 0
    var captureLayoutError: Error?
    var latency: [String: TimeInterval] = ["create": 0.29, "setMain": 0.30, "disable": 0.13, "enable": 0.12,
                                           "release": 0.09, "modes": 0.08, "origins": 0.08]

    /// 物理屏被关（true）/ 开（false）时通知，假 UU 据此让信号消失或回来
    var onPhysicalChange: ((Bool) -> Void)?

    init(scheduler: VirtualScheduler) { self.scheduler = scheduler }

    // MARK: 查询

    func names(_ name: String) -> [Call] { calls.filter { $0.name == name } }
    func count(_ name: String) -> Int { names(name).count }
    var virtualCount: Int { virtuals.count }

    func onlineDisplays() -> [OnlineDisplay] {
        let now = scheduler.now
        let phys = physical.filter { !ledgerDisabled.contains($0) }.map { OnlineDisplay(id: $0, isSnugVirtual: false) }
        let virt = virtuals.filter { ($0.value.onlineAt.map { $0 <= now } ?? false) && !forcedOffline.contains($0.key) }.keys.sorted()
            .map { OnlineDisplay(id: $0, isSnugVirtual: true) }
        let linger = lingering.filter { $0.value.until > now }.keys.sorted().map { OnlineDisplay(id: $0, isSnugVirtual: true) }
        return phys + virt + linger
    }

    /// 真正被关着的物理屏（和磁盘记录分开：模拟别的进程已恢复、记录还在等情况）
    private(set) var ledgerDisabled: Set<DisplayID> = []

    func disabledPhysicalDisplays() -> [DisplayID] { ledger }
    func hasLayoutSnapshot() -> Bool { layoutRecord }

    // MARK: 动作

    func captureLayout() throws {
        log("captureLayout", [])
        if let e = captureLayoutError { throw e }
        layoutRecord = true
    }

    func createVirtual(_ request: VirtualDisplayRequest, completion: @escaping @MainActor @Sendable (VirtualCreateResult) -> Void) {
        log("create", [])
        let now = scheduler.now
        let sameSerialOnline = virtuals.contains { $0.value.serial == request.serial }
            || lingering.contains { $0.value.serial == request.serial && $0.value.until > now }
        later("create") { [self] in
            if sameSerialOnline { return completion(.failed("同序列号的屏还在")) }
            let id = nextID
            nextID += 1
            let onlineAt = onlineDelay.map { scheduler.now.addingTimeInterval($0) }
            virtuals[id] = (request.serial, applySettingsFails ? nil : onlineAt)
            completion(applySettingsFails ? .applyFailed(id) : .created(id))
        }
    }

    func releaseVirtual(_ ids: [DisplayID], completion: @escaping @MainActor @Sendable () -> Void) {
        log("release", ids)
        later("release") { [self] in
            for id in ids {
                guard let v = virtuals.removeValue(forKey: id) else { continue }
                if lingerAfterRelease > 0, v.onlineAt != nil {
                    lingering[id] = (v.serial, scheduler.now.addingTimeInterval(lingerAfterRelease))
                }
            }
            completion()
        }
    }

    func setMain(_ id: DisplayID, completion: @escaping @MainActor @Sendable (TransactionOutcome) -> Void) {
        log("setMain", [id])
        later("setMain") { [self] in completion(setMainError.map { .failure($0) } ?? .success) }
    }

    func disablePhysical(_ ids: [DisplayID], completion: @escaping @MainActor @Sendable (TransactionOutcome) -> Void) {
        log("disable", ids)
        ledger = Array(Set(ledger + ids)).sorted()
        later("disable") { [self] in
            if let e = disableError {
                ledger.removeAll { ids.contains($0) }
                return completion(.failure(e))
            }
            ledgerDisabled.formUnion(ids)
            onPhysicalChange?(true)
            completion(.success)
        }
    }

    func enablePhysical(_ ids: [DisplayID], completion: @escaping @MainActor @Sendable (PhysicalRestoreResult) -> Void) {
        log("enable", ids)
        later("enable") { [self] in
            if !enableFails.isDisjoint(with: ids) {
                return completion(PhysicalRestoreResult(restored: [], failed: ids, failure: .cgError(1000)))
            }
            ledgerDisabled.subtract(ids)
            ledger.removeAll { ids.contains($0) }
            onPhysicalChange?(false)
            completion(PhysicalRestoreResult(restored: ids, failed: [], failure: nil))
        }
    }

    func forgetDisabled(_ ids: [DisplayID]) throws {
        log("forget", ids)
        ledger.removeAll { ids.contains($0) }
    }

    func restoreModes(completion: @escaping @MainActor @Sendable (TransactionOutcome) -> Void) {
        log("restoreModes", [])
        later("modes") { completion(.success) }
    }

    func restoreOrigins(completion: @escaping @MainActor @Sendable (TransactionOutcome) -> Void) {
        log("restoreOrigins", [])
        later("origins") { [self] in
            if restoreOriginsFailuresLeft > 0 {
                restoreOriginsFailuresLeft -= 1
                return completion(.failure(.cgError(1000)))
            }
            layoutRecord = false
            completion(.success)
        }
    }

    // MARK: 模拟外部进程

    /// 看门狗在别的进程里恢复了物理屏并删了记录
    func watchdogRestoredEverything() {
        ledgerDisabled.removeAll()
        ledger.removeAll()
    }

    private func log(_ name: String, _ ids: [DisplayID]) { calls.append(Call(at: scheduler.now, name: name, ids: ids)) }

    private func later(_ key: String, _ block: @escaping @MainActor @Sendable () -> Void) {
        scheduler.after(latency[key] ?? 0, block)
    }
}
