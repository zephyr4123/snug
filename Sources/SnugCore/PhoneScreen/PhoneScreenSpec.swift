// 手机屏的规格：尺寸、像素、物理尺寸和身份。数值全部实测过（见记忆 project-phone-screen）
import Foundation

public enum Orientation: String, Codable, Sendable {
    case portrait, landscape

    public var flipped: Orientation { self == .portrait ? .landscape : .portrait }
}

public struct PhoneScreenSpec: Equatable, Sendable {
    /// 在「显示器」设置和 UU远程 的屏幕列表里看到的名字
    public static let name = "Snug 手机屏"
    /// 'SN'：认出自己建的屏
    public static let vendorID: UInt32 = 0x534E
    public static let productID: UInt32 = 0x00F0
    /// 底部小横条（点一下回到窗口列表）占的高度，放上来的窗口让出这一条
    public static let homeBarHeight = 28.0
    /// 建好不到这么久就释放会让 WindowServer 卡死（原作者实测）
    public static let minimumLifetime: TimeInterval = 2.5

    public let orientation: Orientation

    public init(_ orientation: Orientation) { self.orientation = orientation }

    /// 逻辑尺寸（点）。按 UU 在 iPhone 17 Pro Max 上不被遮挡的区域定比例：
    /// 竖屏底部 UU 工具栏约 268px，横屏左边灵动岛 216px、右边侧栏 240px。UU 按比例居中显示，
    /// 比手机窄出来的部分正好落在被遮挡的地方。短边 540 是 2 倍高清的门槛：再小，系统就只给 1 倍
    public var width: Int { orientation == .portrait ? 540 : 976 }
    public var height: Int { orientation == .portrait ? 950 : 540 }
    public var pixelWidth: Int { width * 2 }
    public var pixelHeight: Int { height * 2 }

    /// 物理尺寸按约 220ppi 折算。按手机的真实密度（460ppi）算，全新身份的屏永远不上线，
    /// 而且这个身份从此被系统「拉黑」，改回来也不行
    public var millimeters: (width: Double, height: Double) {
        (Double(pixelWidth) / 220 * 25.4, Double(pixelHeight) / 220 * 25.4)
    }

    /// 身份（序列号）：每个方向固定一个，建了不上线就依次换备用的。
    /// 固定身份能让系统记住这块屏的设置；每多用一个新身份，系统就多存一份 ICC 文件
    public var serials: [UInt32] {
        let first: UInt32 = orientation == .portrait ? 200_000_008 : 200_000_007
        return [first, first + 10, first + 20]
    }
}
