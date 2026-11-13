// 一次远程会话（episode）的生命周期，与具体功能无关。
// 连入时开始；断开后进入重连窗口，窗口内再连入算同一会话，按会话生效的标记（手动叫停等）保留；
// 窗口过了会话结束，标记清空。这样信号抖一下不会让「本次远程别再调整」之类的决定失效
import Foundation

public enum EpisodeChange: Equatable, Sendable {
    case began, resumed, interrupted, ended
}

public struct SessionEpisode: Sendable {
    public static let reconnectWindow: TimeInterval = 15

    private enum Phase: Sendable {
        case idle
        case live
        case interrupted(since: Date)
    }

    private var phase = Phase.idle
    /// 用户在本会话里手动叫停了 Snug 的调整（热键 / 菜单）
    public private(set) var suspendedByUser = false

    public init() {}

    /// 会话进行中（含断开后的重连窗口）
    public var isActive: Bool {
        if case .idle = phase { return false }
        return true
    }

    public mutating func connected(at now: Date) -> EpisodeChange {
        if advance(to: now) == .ended { return began() }
        switch phase {
        case .idle: return began()
        case .live, .interrupted:
            phase = .live
            return .resumed
        }
    }

    public mutating func disconnected(at now: Date) -> EpisodeChange? {
        guard case .live = phase else { return nil }
        phase = .interrupted(since: now)
        return .interrupted
    }

    /// 重连窗口过了就结束会话
    public mutating func advance(to now: Date) -> EpisodeChange? {
        guard case .interrupted(let since) = phase, now.timeIntervalSince(since) > Self.reconnectWindow else { return nil }
        phase = .idle
        suspendedByUser = false
        return .ended
    }

    /// 会话进行中才生效并返回 true；不在会话中按热键只是恢复一下，不影响下一次远程（修 B11）
    public mutating func suspendByUser() -> Bool {
        guard isActive else { return false }
        suspendedByUser = true
        return true
    }

    private mutating func began() -> EpisodeChange {
        phase = .live
        suspendedByUser = false
        return .began
    }
}
