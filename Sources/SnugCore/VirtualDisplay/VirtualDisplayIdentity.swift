// 虚拟屏的身份：名称、厂商 / 产品号、稳定序列号。
// 稳定序列号的思路来自社区 PR #14（作者 bubble）：旧版每次建屏随机 serialNum，macOS 把每块屏都当成新显示器，
// 在 /Library/ColorSync/Profiles/Displays 生成一个新 ICC 文件且从不回收（主人机器上 4 次建屏留下 4 个）。
// 同一配置固定序列号后，同一台控制设备永远对应同一个显示器身份
import Foundation

public enum VirtualDisplayIdentity {
    /// 'SN'：本工具的虚拟屏都用这个厂商号，凭它把自己的屏和物理屏分开。改了它所有身份都会换一遍，别动
    public static let vendorID: UInt32 = 0x534E
    public static let productID: UInt32 = 0x0001

    /// 显示在 UU 的多显示屏列表、系统「显示器」设置里
    public static func name(for profile: DeviceProfile) -> String { "Snug · \(profile.name)" }

    /// FNV-1a 32 位，key 为「名字|宽x高|高清」。不能用 Swift 的 Hasher：它每次进程启动都随机加盐
    public static func serial(for profile: DeviceProfile) -> UInt32 {
        serial(fromHash: fnv1a("\(profile.name)|\(profile.width)x\(profile.height)|\(profile.hiDPI ? 1 : 0)"))
    }

    static func fnv1a(_ key: String) -> UInt32 {
        var hash: UInt32 = 2_166_136_261
        for byte in key.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return hash
    }

    /// 落到 1...0xFFFF_FFEF；0 不是合法序列号
    static func serial(fromHash hash: UInt32) -> UInt32 {
        let serial = hash % 0xFFFF_FFF0
        return serial == 0 ? 1 : serial
    }
}
