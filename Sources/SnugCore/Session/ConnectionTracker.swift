// 连接判定（纯值类型，now 由调用方传入）：把每拍的 UU 观测合成连入 / 换控制端 / 断开。
// - 连入要快：未连接时一看到在场就连入，不做确认延迟
// - 断开要稳，同时满足三条才判：
//   1. 连续不在场超过 disconnectDebounce（UU 切屏时覆盖窗口会短暂重建）
//   2. 过了自扰静默期：本工具自己加屏、撤屏后 quietWindow 内不判。屏幕组合一变，UU 会停流重开、重建窗口，
//      2026-11-12 19:01 就因为改屏幕扰乱了 UU 的信号被误判为断开，屏幕改回去信号又回来，如此反复
//   3. 推流不在进行；推流还在但其余信号已连续缺席超过 maxCaptureVeto 时也判（安全上限，防推流日志误判让手机屏一直撤不掉）。
//      上限生效后，这段卡住的「推流中」不再算在场，直到推流状态先变成非 true 再重新开始
import Foundation

public struct ConnectionTracker: Sendable {
    public static let disconnectDebounce: TimeInterval = 1.5
    public static let quietWindow: TimeInterval = 5
    public static let maxCaptureVeto: TimeInterval = 60

    public private(set) var isConnected = false
    public private(set) var controller: String?

    private var connectedAt: Date?
    private var lastPresentAt: Date?
    private var lastUIPresentAt: Date?
    private var quietUntil: Date?
    /// 推流否决上限已经用过：卡住的 true 不再算在场
    private var captureDistrusted = false

    public init() {}

    /// 本工具即将或刚刚引起屏幕 / 窗口扰动（改显示拓扑、挪窗口……）时调用
    public mutating func noteSelfInducedChange(at date: Date) {
        let until = date.addingTimeInterval(Self.quietWindow)
        quietUntil = max(quietUntil ?? until, until)
    }

    public mutating func update(_ signals: UUSignals, now: Date) -> ConnectionEvent? {
        if signals.captureActive != true { captureDistrusted = false }
        let captureCounts = signals.captureActive == true && !captureDistrusted
        let present = signals.uiPresent || captureCounts
        if signals.uiPresent { lastUIPresentAt = now }
        if present { lastPresentAt = now }

        guard isConnected else {
            guard present else { return nil }
            isConnected = true
            connectedAt = now
            controller = signals.controllers?.first
            log("检测到 UU 连入", signals, now: now)
            return .connected(controller: controller)
        }

        if present {
            if let name = signals.controllers?.first, name != controller {
                controller = name
                log("控制端变为 \(name)", signals, now: now)
                return .controllerChanged(name)
            }
            if !captureCounts || signals.uiPresent { return nil }
            // 只剩推流在撑着：看是否超过否决上限
            let uiSince = max(lastUIPresentAt ?? .distantPast, connectedAt ?? now)
            guard now.timeIntervalSince(uiSince) > Self.maxCaptureVeto, quietPassed(now) else { return nil }
            captureDistrusted = true
            Log.warn("推流信号持续 \(Int(Self.maxCaptureVeto))s 以上没有其余信号佐证，按安全上限判为断开")
            return disconnect(signals, now: now)
        }

        guard let last = lastPresentAt, now.timeIntervalSince(last) > Self.disconnectDebounce, quietPassed(now) else { return nil }
        return disconnect(signals, now: now)
    }

    private func quietPassed(_ now: Date) -> Bool {
        guard let until = quietUntil else { return true }
        return now > until
    }

    private mutating func disconnect(_ signals: UUSignals, now: Date) -> ConnectionEvent {
        log("检测到 UU 断开", signals, now: now)
        isConnected = false
        controller = nil
        connectedAt = nil
        return .disconnected
    }

    /// 每次连接事件都留下信号快照，排查误判时才知道是哪一路信号在变
    private func log(_ what: String, _ signals: UUSignals, now: Date) {
        let since = lastPresentAt.map { String(format: "%.2f", now.timeIntervalSince($0)) } ?? "-"
        let quiet = quietUntil.map { now <= $0 ? String(format: " 静默期剩 %.2fs", $0.timeIntervalSince(now)) : "" } ?? ""
        Log.info("\(what)（\(signals) 距上次在场 \(since)s\(quiet)）")
    }
}
