// 看门狗的判定规则（纯值类型，now 由调用方给）。看门狗是独立进程，只在磁盘上有熄屏记录时才可能出手。
// 判断依据只有主程序每秒写的 app-state.json（修 B3）：旧版看门狗自己去看 UU 的覆盖窗口，
// 主程序却也认控制端表格，没有覆盖窗口的会话里看门狗会在远程进行中把物理屏点亮。
// 现在全仓只有主程序一套连接判定，看门狗只看主程序在不在、卡没卡、还要不要熄屏
import Foundation

public struct WatchdogObservation: Equatable, Sendable {
    /// disabled-displays.json 里有待恢复的物理屏
    public var hasDisabledPhysical: Bool
    /// app-state.json 的内容；nil = 没有这个文件或读不出来
    public var appState: AppStateRecord?
    /// app-state.json 的修改时间距今多久（mtime 即心跳）
    public var heartbeatAge: TimeInterval?
    /// 记录里的 pid 还活着，而且确实是 Snug（pid 可能已被别的进程复用）
    public var appProcessAlive: Bool

    public init(hasDisabledPhysical: Bool, appState: AppStateRecord?, heartbeatAge: TimeInterval?, appProcessAlive: Bool) {
        self.hasDisabledPhysical = hasDisabledPhysical
        self.appState = appState
        self.heartbeatAge = heartbeatAge
        self.appProcessAlive = appProcessAlive
    }
}

public enum WatchdogVerdict: Equatable, Sendable {
    public enum Reason: Equatable, Sendable, CustomStringConvertible {
        case appGone
        case appStuck(seconds: Int)
        case intentLapsed

        public var description: String {
            switch self {
            case .appGone: "主程序不在"
            case .appStuck(let s): "主程序卡住 \(s) 秒没有心跳"
            case .intentLapsed: "主程序已不需要熄屏，物理屏却还关着"
            }
        }
    }

    case idle
    case restore(reason: Reason)
    /// 主程序卡死：先结束它（不然它醒过来可能接着熄屏），再恢复
    case killThenRestore(pid: Int32, reason: Reason)
}

public struct WatchdogJudge: Sendable {
    /// 主程序每秒写一次心跳；超过这么久没写，就是主线程卡死了
    public static let heartbeatTimeout: TimeInterval = 10
    /// 主程序健康、已经不要熄屏了，它自己的执行器会立刻恢复物理屏；连续这么久还没恢复，看门狗才接手
    public static let intentLapseLimit: TimeInterval = 10

    private var lapsedSince: Date?

    public init() {}

    public mutating func evaluate(_ o: WatchdogObservation, now: Date) -> WatchdogVerdict {
        guard o.hasDisabledPhysical else {
            lapsedSince = nil
            return .idle
        }
        guard let app = o.appState, o.appProcessAlive else {
            lapsedSince = nil
            return .restore(reason: .appGone)
        }
        if let age = o.heartbeatAge, age > Self.heartbeatTimeout {
            lapsedSince = nil
            return .killThenRestore(pid: app.pid, reason: .appStuck(seconds: Int(age)))
        }
        if app.keepOnlyVirtualActive {
            lapsedSince = nil
            return .idle
        }
        let since = lapsedSince ?? now
        lapsedSince = since
        return now.timeIntervalSince(since) > Self.intentLapseLimit ? .restore(reason: .intentLapsed) : .idle
    }
}
