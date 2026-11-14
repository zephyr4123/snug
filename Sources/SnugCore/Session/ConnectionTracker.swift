// 连接判定（纯值类型，now 由调用方传入）：把每拍的 UU 观测合成连入 / 换控制端 / 断开。
// - 在场只认正面证据（UUSignals.isPresent）：覆盖窗口在屏、认出了控制端、推流在进行，有一路就算
// - 连入要快：未连接时一看到在场就连入，不做确认延迟
// - 断开要稳，同时满足两条才判：
//   1. 连续不在场超过 disconnectDebounce（UU 切屏时覆盖窗口会短暂重建）
//   2. 过了自扰静默期：本工具自己加屏、撤屏后 quietWindow 内不判。屏幕组合一变，UU 会停流重开、重建窗口，
//      2026-11-12 19:01 就因为改屏幕扰乱了 UU 的信号被误判为断开，屏幕改回去信号又回来，如此反复
// - 推流还在就算远程还在，不设「推流太久就判断开」的上限。上限得靠控制端表格证明「没人」，
//   可 UU 没被控时根本不显示这张表，没认出控制端只说明没看到：先是 UU 主窗口关着、后是停在首页（issue #1），
//   正常远程都被上限误判断开过，而它一次也没在真正该断的时候起过作用。
//   代价是停流的日志万一全漏掉，手机屏会一直留着：菜单栏照样显示「远程中」，在设置里关掉手机屏或退出 Snug 就能复原
import Foundation

public struct ConnectionTracker: Sendable {
    public static let disconnectDebounce: TimeInterval = 1.5
    public static let quietWindow: TimeInterval = 5

    public private(set) var isConnected = false
    public private(set) var controller: String?

    private var lastPresentAt: Date?
    private var quietUntil: Date?

    public init() {}

    /// 本工具即将或刚刚引起屏幕 / 窗口扰动（改显示拓扑、挪窗口……）时调用
    public mutating func noteSelfInducedChange(at date: Date) {
        let until = date.addingTimeInterval(Self.quietWindow)
        quietUntil = max(quietUntil ?? until, until)
    }

    public mutating func update(_ signals: UUSignals, now: Date) -> ConnectionEvent? {
        let name = signals.controllers.names.first
        if signals.isPresent { lastPresentAt = now }

        guard isConnected else {
            guard signals.isPresent else { return nil }
            isConnected = true
            controller = name
            log("检测到 UU 连入", signals, now: now)
            return .connected(controller: controller)
        }

        if signals.isPresent {
            // 没认出控制端时保留原名：主窗口切走了不代表换了人
            guard let name, name != controller else { return nil }
            controller = name
            log("控制端变为 \(name)", signals, now: now)
            return .controllerChanged(name)
        }

        guard let last = lastPresentAt, now.timeIntervalSince(last) > Self.disconnectDebounce, quietPassed(now) else { return nil }
        log("检测到 UU 断开", signals, now: now)
        isConnected = false
        controller = nil
        return .disconnected
    }

    private func quietPassed(_ now: Date) -> Bool {
        guard let until = quietUntil else { return true }
        return now > until
    }

    /// 每次连接事件都留下信号快照，排查误判时才知道是哪一路信号在变
    private func log(_ what: String, _ signals: UUSignals, now: Date) {
        let since = lastPresentAt.map { String(format: "%.2f", now.timeIntervalSince($0)) } ?? "-"
        let quiet = quietUntil.map { now <= $0 ? String(format: " 静默期剩 %.2fs", $0.timeIntervalSince(now)) : "" } ?? ""
        Log.info("\(what)（\(signals) 距上次在场 \(since)s\(quiet)）")
    }
}
