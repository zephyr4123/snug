// disabled-displays.json：被禁用、待恢复的物理屏。先写盘再禁用——被禁用的屏会从在线列表里消失，
// 不记下 ID 就再也找不回来；看门狗、snug-rescue 和主程序都按这份记录恢复
import Foundation

public struct PhysicalDisplayRecord: Codable, Equatable, Sendable {
    public var displays: [DisplayID]

    public init(displays: [DisplayID]) { self.displays = displays }
}
