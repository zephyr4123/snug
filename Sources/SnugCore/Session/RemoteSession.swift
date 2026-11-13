// 会话层的组合：连接判定 + 会话生命周期，把每拍观测变成功能模块要处理的会话变化。
// 各功能模块（虚拟屏等）只消费 SessionTransition，会话层不知道有哪些功能
import Foundation

public enum SessionTransition: Equatable, Sendable {
    /// 新会话开始
    case began(controller: String?)
    /// 重连窗口内再连上，仍是同一会话
    case resumed(controller: String?)
    case controllerChanged(String)
    /// 断开，进入重连窗口
    case interrupted
    /// 重连窗口过了，会话结束
    case ended
}

public struct RemoteSession: Sendable {
    public private(set) var tracker = ConnectionTracker()
    public private(set) var episode = SessionEpisode()

    public init() {}

    public var isConnected: Bool { tracker.isConnected }
    public var controller: String? { tracker.controller }
    public var inEpisode: Bool { episode.isActive }
    public var suspendedByUser: Bool { episode.suspendedByUser }

    public mutating func update(_ signals: UUSignals, now: Date) -> [SessionTransition] {
        var out: [SessionTransition] = []
        if episode.advance(to: now) == .ended { out.append(.ended) }
        switch tracker.update(signals, now: now) {
        case .connected(let name)?:
            out.append(episode.connected(at: now) == .began ? .began(controller: name) : .resumed(controller: name))
        case .controllerChanged(let name)?:
            out.append(.controllerChanged(name))
        case .disconnected?:
            if episode.disconnected(at: now) == .interrupted { out.append(.interrupted) }
        case nil:
            break
        }
        return out
    }

    public mutating func noteSelfInducedChange(at date: Date) {
        tracker.noteSelfInducedChange(at: date)
    }

    @discardableResult
    public mutating func suspendByUser() -> Bool { episode.suspendByUser() }
}
