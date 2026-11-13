// 显示执行器的时间常数。前几项是原作者实测出来的硬约束，改之前先读注释
import Foundation

public enum DisplayTiming {
    // 一次只做一步拓扑变化，每步之后等系统稳定。原作者实测：重新启用物理屏的热插拔还没处理完就建虚拟屏，
    // applySettings 失败，随后 WindowServer 在 GenerateModeListForDisplay 中 abort，系统注销重启
    public static let settleAfterCreate: TimeInterval = 1.0
    public static let settleAfterSetMain: TimeInterval = 0.5
    public static let settleAfterRelease: TimeInterval = 1.5
    public static let settleAfterPhysical: TimeInterval = 1.5
    public static let settleAfterLayout: TimeInterval = 0.5

    // 虚拟屏建好约 1 秒、还没完全上线时就释放，会让 WindowServer 显示配置卡死（所有事务 10 秒超时，要重启才恢复）。
    // 所以释放前必须已上线且存活 ≥2.5s；从出生算最多等 8s，再强制释放
    public static let minLifetimeBeforeRelease: TimeInterval = 2.5
    public static let maxReleaseWait: TimeInterval = 8

    /// 虚拟屏建好后这么久还没上线，按建屏失败处理（绝不接着关物理屏，修 B7）
    public static let onlineTimeout: TimeInterval = 5
    /// 等上线、等释放条件时的轮询间隔
    public static let pollInterval: TimeInterval = 0.25

    /// 断开宽限：目标变成「无」时物理屏立刻恢复，虚拟屏再留这么久，宽限内同规格的目标回来就直接复用
    public static let releaseGrace: TimeInterval = 10

    /// 恢复物理屏失败后按 ID 分开重试的间隔，最后一档之后每 30s 慢速重试（修 B2）
    public static let restoreBackoff: [TimeInterval] = [1.5, 3, 6, 12, 30]
    /// 同一 ID 连续失败这么多次就从记录里丢弃（多半是外接屏被拔了），约 2.4 分钟
    public static let maxRestoreFailures = 8

    /// 布局还原（模式 + 原点）失败后的重试间隔；用完就放弃，记录保留到下次启动或菜单「还原布局」
    public static let layoutRetryDelays: [TimeInterval] = [1, 3]

    /// 同身份（同序列号）的旧屏释放后还在在线列表里时，最多等它这么久再建新屏（不退回随机号，免得多一个 ICC 文件）
    public static let sameSerialWait: TimeInterval = 5

    static func restoreDelay(afterFailures n: Int) -> TimeInterval {
        restoreBackoff[min(max(n, 1), restoreBackoff.count) - 1]
    }
}
