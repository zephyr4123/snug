// 用户设置（config.json）。App 层的 AppController 是唯一写入者
import Foundation

public struct AppConfig: Codable, Equatable, Sendable {
    public var devices: [DeviceProfile] = []
    /// 总开关：暂停 Snug 的一切调整（连接检测照常，只是什么都不改）
    public var paused = false
    /// 可选功能：远程时按控制端设备建同分辨率的虚拟屏。默认关闭——UU远程 自己的屏幕处理已经够好
    public var virtualDisplayEnabled = false
    /// 远程时只保留虚拟屏（熄灭物理屏）；只在 virtualDisplayEnabled 打开时才有意义
    public var keepOnlyVirtual = false
    /// 看门狗（兜底恢复物理屏）
    public var watchdogEnabled = false
    /// 是否已看过首次启动功能导览
    public var tourShown = false

    public init() {}

    public func device(named name: String?) -> DeviceProfile? {
        guard let name else { return nil }
        return devices.first { $0.name == name }
    }

    private enum CodingKeys: String, CodingKey {
        case devices, paused, virtualDisplayEnabled, keepOnlyVirtual, watchdogEnabled, tourShown
    }

    // 每一项都有默认值：以后加字段、或者手改漏了某项，都不会让整份配置被判为损坏
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppConfig()
        devices = try c.decodeIfPresent([DeviceProfile].self, forKey: .devices) ?? d.devices
        paused = try c.decodeIfPresent(Bool.self, forKey: .paused) ?? d.paused
        virtualDisplayEnabled = try c.decodeIfPresent(Bool.self, forKey: .virtualDisplayEnabled) ?? d.virtualDisplayEnabled
        keepOnlyVirtual = try c.decodeIfPresent(Bool.self, forKey: .keepOnlyVirtual) ?? d.keepOnlyVirtual
        watchdogEnabled = try c.decodeIfPresent(Bool.self, forKey: .watchdogEnabled) ?? d.watchdogEnabled
        tourShown = try c.decodeIfPresent(Bool.self, forKey: .tourShown) ?? d.tourShown
    }
}
