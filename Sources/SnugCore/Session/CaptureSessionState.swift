// 由推流事件推出「此刻 UU 是否在推流」（纯值类型，时间由调用方给）。
// active：从推流开始算起，到「终止事件之后 restartGrace 内没有任何重新开始的迹象」为止。
// 「重新开始」除了新的推流开始，还包括新建编码会话：2026-11-12 的真实日志里，UU 会在推流中途
// 结束一个编码会话（带 encoded 摘要）再立刻新建一个，不发新的推流开始——
// 19:01:23.822 结束、23.831 新建，推流一直持续到 43.417；17:56:34.133 结束、.136 新建，持续到 18:00:52。
// 只认推流开始的话，这两段会在会话进行中误判为已停流。
// 探测性的编码会话（没有 encoded 摘要）不算终止；单独出现的新建编码会话也不会让状态变成推流中
// （UU 进程启动时会成批试探编码参数）。
// 顺带记下「UU 在推哪块屏」：推流开始前最后一次被描述的那块屏（UU 先枚举全部屏幕，再为要推的那块建过滤器、开推）。
// UU 一次远程开头会先后起两路推流：第一路是画面，推用户在看的那块；紧跟着（中间没有终止）再起一路常驻的，
// 开推前描述的总是主屏，一直推到远程结束。这第二路不能盖掉第一路的屏——
// 22:57:12.969 先为 79（手机屏）开推，13.023 又为 1 开推，画面一直在 79 上
import Foundation

public struct CaptureSessionState: Sendable {
    /// 终止事件之后等这么久，没有重新开始才算真的停了（加屏、撤屏等屏幕组合变化时 UU 会停流再重开）
    public static let restartGrace: TimeInterval = 3

    private var active = false
    private var pendingEndAt: Date?
    private var lastDescribed: DisplayID?
    private var captured: DisplayID?
    /// 上次推流开始之后见过终止：没见过就是紧跟着起的第二路，不改 captured
    private var stoppedSinceStart = true

    public init() {}

    public mutating func apply(_ record: CaptureLogRecord) {
        settle(before: record.date)
        switch record.event {
        case .displayDescribed(let id):
            lastDescribed = id
        case .captureStarted:
            if !active || stoppedSinceStart { captured = lastDescribed }
            stoppedSinceStart = false
            active = true
            pendingEndAt = nil
        case .encoderCreated:
            pendingEndAt = nil
        case .captureStopped, .encoderEnded:
            stoppedSinceStart = true
            if active, pendingEndAt == nil { pendingEndAt = record.date }
        case .encoderProbeEnded:
            break
        }
    }

    public func isActive(at now: Date) -> Bool {
        guard active else { return false }
        guard let end = pendingEndAt else { return true }
        return now.timeIntervalSince(end) <= Self.restartGrace
    }

    /// 此刻 UU 在推的屏；没在推流、或推流开始前没看到屏的描述时为 nil
    public func streamingDisplay(at now: Date) -> DisplayID? {
        isActive(at: now) ? captured : nil
    }

    /// 日志监听（重新）启动时：先按时间回放启动前的日志（UU 的常驻推流只在远程开头打一次「开始」，不回放就以为没在推），
    /// 再接上启动后收到的；两段重叠的部分按时间去掉
    public static func resumed(history: [CaptureLogRecord], live: [CaptureLogRecord]) -> CaptureSessionState {
        var state = CaptureSessionState()
        for r in history { state.apply(r) }
        let after = history.last?.date ?? .distantPast
        for r in live where r.date > after { state.apply(r) }
        return state
    }

    /// 宽限已过的终止先落定，免得之后来的事件把一段早已结束的推流续上
    private mutating func settle(before date: Date) {
        if active, !isActive(at: date) {
            active = false
            pendingEndAt = nil
            captured = nil
            stoppedSinceStart = true
        }
    }
}
