// disabled-displays.json 的记账与按记录禁用 / 恢复物理屏。主程序（经 CGDisplayDriver）、看门狗、snug-rescue 都用它。
// 先写盘再禁用；按 ID 恢复，成功的从记录里移除，全部恢复才删文件。
// 含 CG 事务的方法都是同步的：GUI 进程里要放在后台队列调用
import CoreGraphics
import Foundation
import SnugCore

public struct PhysicalDisplayLedger: Sendable {
    private let record: RestoreRecord<PhysicalDisplayRecord>

    public init(url: URL) { record = RestoreRecord(url: url) }

    public static var available: Bool { DisplayEnabler.available }

    /// 磁盘上记录的待恢复物理屏
    public func recorded() -> [DisplayID] { record.pending()?.displays ?? [] }

    /// 先把 ID 并进记录，再禁用；事务失败就把刚加的撤掉
    public func disable(_ ids: [DisplayID]) -> TransactionOutcome {
        guard DisplayEnabler.available else { return .failure(.unavailable("CGSConfigureDisplayEnabled 不可用")) }
        let before = recorded()
        do {
            try record.record(PhysicalDisplayRecord(displays: Array(Set(before + ids)).sorted()))
        } catch {
            Log.error("写物理屏记录失败，放弃熄灭 \(ids)：\(error)")
            return .failure(.recordFailed("\(error)"))
        }
        let err = DisplayEnabler.set(ids, enabled: false)
        guard err != .success else { return .success }
        do {
            if before.isEmpty { try record.settle() } else { try record.record(PhysicalDisplayRecord(displays: before)) }
        } catch {
            // 记录里多出没真正禁用的 ID 无害：恢复时会按「已亮着」直接销账
            Log.error("熄灭失败后撤回物理屏记录也失败：\(error)")
        }
        return .failure(.cgError(err.rawValue))
    }

    /// 在一个事务里恢复这些屏。已经在线且启用的（看门狗或系统已恢复）直接算恢复——思路来自社区 PR #12（作者 gencheng liu）：
    /// 对已激活的屏再提交启用事务可能失败，不能因此一直卡在恢复上
    public func restore(_ ids: [DisplayID]) -> PhysicalRestoreResult {
        let already = ids.filter(DisplayList.isOnlineAndActive)
        let remaining = ids.filter { !already.contains($0) }
        var restored = already
        var failed: [DisplayID] = []
        var failure: DisplayFailure?
        if !remaining.isEmpty {
            let err = DisplayEnabler.set(remaining, enabled: true)
            if err == .success {
                restored += remaining
            } else {
                failed = remaining
                failure = .cgError(err.rawValue)
            }
        }
        if !already.isEmpty { Log.info("物理屏 \(already) 已经亮着，直接销账") }
        settle(restored)
        return PhysicalRestoreResult(restored: restored, failed: failed, failure: failure)
    }

    /// 救急用（看门狗、snug-rescue，不在主线程）：先一起恢复，失败了再一块一块单独试，中间停 pause 秒让系统稳定
    public func restoreAll(pause: TimeInterval) -> PhysicalRestoreResult {
        let ids = recorded()
        guard !ids.isEmpty else { return PhysicalRestoreResult(restored: [], failed: [], failure: nil) }
        let joint = restore(ids)
        guard ids.count > 1, !joint.failed.isEmpty else { return joint }
        var restored = joint.restored, failed: [DisplayID] = [], failure = joint.failure
        for id in joint.failed {
            Thread.sleep(forTimeInterval: pause)
            let single = restore([id])
            restored += single.restored
            failed += single.failed
            failure = single.failure ?? failure
        }
        return PhysicalRestoreResult(restored: restored, failed: failed, failure: failed.isEmpty ? nil : failure)
    }

    /// 放弃恢复这些屏（多半已被拔掉）
    public func forget(_ ids: [DisplayID]) throws {
        let left = recorded().filter { !ids.contains($0) }
        if left.isEmpty { try record.settle() } else { try record.record(PhysicalDisplayRecord(displays: left)) }
    }

    /// 恢复成功的从记录里移除，全部恢复才删文件。记账失败只记日志：屏已经亮了，下次恢复会按「已亮着」销账
    private func settle(_ restored: [DisplayID]) {
        guard !restored.isEmpty else { return }
        do { try forget(restored) } catch {
            Log.error("物理屏 \(restored) 已恢复，但更新记录失败：\(error)")
        }
    }
}
