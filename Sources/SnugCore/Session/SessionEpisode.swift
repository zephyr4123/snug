// 一次远程会话（episode）的生命周期，与具体功能无关。
// 连入时开始；断开后进入重连窗口，窗口内再连入算同一会话；窗口过了会话才结束。
// 这样信号抖一下、或者手机短暂断网，手机屏和上面的窗口都还在，重连回来接着用
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
        return .ended
    }

    private mutating func began() -> EpisodeChange {
        phase = .live
        return .began
    }
}
