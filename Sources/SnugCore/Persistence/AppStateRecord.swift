// app-state.json：主程序每秒发布一次自己的状态。看门狗只认这份记录判断会话，
// 不再自己去看 UU 的窗口（旧版看门狗只看覆盖窗口，和主程序的判断不一致，会在远程中途点亮物理屏）
import Foundation

public struct AppStateRecord: Codable, Equatable, Sendable {
    public var pid: Int32
    public var updatedAt: Date
    public var connected: Bool
    /// 此刻是否有意让物理屏保持熄灭
    public var keepOnlyVirtualActive: Bool

    public init(pid: Int32, updatedAt: Date, connected: Bool, keepOnlyVirtualActive: Bool) {
        self.pid = pid
        self.updatedAt = updatedAt
        self.connected = connected
        self.keepOnlyVirtualActive = keepOnlyVirtualActive
    }
}
