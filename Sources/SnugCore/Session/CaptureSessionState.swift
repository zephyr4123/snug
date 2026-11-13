// 由推流事件推出「此刻 UU 是否在推流」（纯值类型，时间由调用方给）。
// active：从推流开始算起，到「终止事件之后 restartGrace 内没有任何重新开始的迹象」为止。
// 「重新开始」除了新的推流开始，还包括新建编码会话：2026-11-12 的真实日志里，UU 会在推流中途
// 结束一个编码会话（带 encoded 摘要）再立刻新建一个，不发新的推流开始——
// 19:01:23.822 结束、23.831 新建，推流一直持续到 43.417；17:56:34.133 结束、.136 新建，持续到 18:00:52。
// 只认推流开始的话，这两段会在会话进行中误判为已停流。
// 探测性的编码会话（没有 encoded 摘要）不算终止；单独出现的新建编码会话也不会让状态变成推流中
// （UU 进程启动时会成批试探编码参数）
import Foundation

public struct CaptureSessionState: Sendable {
    /// 终止事件之后等这么久，没有重新开始才算真的停了（关物理屏等拓扑变化时 UU 会停流再重开）
    public static let restartGrace: TimeInterval = 3

    private var active = false
    private var pendingEndAt: Date?

    public init() {}

    public mutating func apply(_ record: CaptureLogRecord) {
        settle(before: record.date)
        switch record.event {
        case .captureStarted:
            active = true
            pendingEndAt = nil
        case .encoderCreated:
            pendingEndAt = nil
        case .captureStopped, .encoderEnded:
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

    /// 宽限已过的终止先落定，免得之后来的事件把一段早已结束的推流续上
    private mutating func settle(before date: Date) {
        if active, !isActive(at: date) {
            active = false
            pendingEndAt = nil
        }
    }
}
