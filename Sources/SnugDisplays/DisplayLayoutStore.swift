// 物理屏布局快照（layout.json）的采集与还原。还原分两个事务：先模式、再原点；原点成功才删记录。
// 含 CG 事务的方法都是同步的：GUI 进程里要放在后台队列调用
import CoreGraphics
import Foundation
import SnugCore

public struct DisplayLayoutStore: Sendable {
    private let record: RestoreRecord<LayoutSnapshot>

    public init(url: URL) { record = RestoreRecord(url: url) }

    public func pending() -> LayoutSnapshot? { record.pending() }

    /// 采集当前在线物理屏（不含本工具的虚拟屏）的原点与显示模式，写进 layout.json。写不进去就抛错
    public func captureAndSave(now: Date = Date()) throws -> LayoutSnapshot {
        let entries = DisplayList.online().filter { !DisplayList.isSnugVirtual($0) }.map { id in
            let origin = CGDisplayBounds(id).origin
            return DisplayLayoutEntry(id: id, originX: Int(origin.x), originY: Int(origin.y),
                                      mode: CGDisplayCopyDisplayMode(id).map(Self.info))
        }
        let snapshot = LayoutSnapshot(capturedAt: now, displays: entries)
        try record.record(snapshot)
        Log.info("已记录屏幕布局：\(entries.map { "#\($0.id)@\($0.originX),\($0.originY) \($0.mode.map { "\($0.width)×\($0.height)@\(Int($0.refreshRate))" } ?? "模式未知")" })")
        return snapshot
    }

    /// 恢复各屏的显示模式（一个事务）。当前模式已对的跳过；不在线、找不到原模式的记 warn 后跳过（退化成只还原原点）
    public func restoreModes(_ snapshot: LayoutSnapshot) -> TransactionOutcome {
        let online = Set(DisplayList.online())
        var changes: [(DisplayID, CGDisplayMode)] = []
        for entry in snapshot.displays {
            guard let saved = entry.mode else { continue }
            guard online.contains(entry.id) else {
                Log.warn("物理屏 #\(entry.id) 不在线，跳过模式还原")
                continue
            }
            if let current = CGDisplayCopyDisplayMode(entry.id), DisplayModeMatcher.isSame(Self.info(current), as: saved) { continue }
            let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
            let modes = (CGDisplayCopyAllDisplayModes(entry.id, options) as? [CGDisplayMode]) ?? []
            guard let i = DisplayModeMatcher.bestMatch(for: saved, in: modes.map(Self.info)) else {
                Log.warn("找不到物理屏 #\(entry.id) 原来的模式 \(saved.width)×\(saved.height)@\(saved.refreshRate)，只还原原点")
                continue
            }
            changes.append((entry.id, modes[i]))
        }
        guard !changes.isEmpty else { return .success }
        return TransactionOutcome(applyDisplayConfig { config in
            for (id, mode) in changes {
                let err = CGConfigureDisplayWithDisplayMode(config, id, mode, nil)
                if err != .success { return err }
            }
            return .success
        })
    }

    /// 恢复各屏原点（一个事务）；成功后删记录。快照里的屏都不在线（例如重启后编号变了）时记 warn 并删记录
    public func restoreOrigins(_ snapshot: LayoutSnapshot) -> TransactionOutcome {
        let online = Set(DisplayList.online())
        let targets = snapshot.displays.filter { online.contains($0.id) }
        let missing = snapshot.displays.filter { !online.contains($0.id) }.map(\.id)
        if !missing.isEmpty { Log.warn("物理屏 \(missing) 不在线，跳过原点还原") }
        if !targets.isEmpty {
            let err = applyDisplayConfig { config in
                for t in targets {
                    let e = CGConfigureDisplayOrigin(config, t.id, Int32(t.originX), Int32(t.originY))
                    if e != .success { return e }
                }
                return .success
            }
            guard err == .success else { return .failure(.cgError(err.rawValue)) }
        }
        do {
            try record.settle()
        } catch {
            return .failure(.recordFailed("布局已还原，但删除 layout.json 失败：\(error)"))
        }
        return .success
    }

    static func info(_ mode: CGDisplayMode) -> DisplayModeInfo {
        DisplayModeInfo(ioDisplayModeID: mode.ioDisplayModeID, width: mode.width, height: mode.height,
                        pixelWidth: mode.pixelWidth, pixelHeight: mode.pixelHeight, refreshRate: mode.refreshRate)
    }
}
