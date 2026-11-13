// 手机屏的规格：尺寸、像素、物理尺寸和身份。数值全部实测过（见记忆 project-phone-screen）。
// 只有竖屏一种：原版 UU 本来就是横屏，Snug 补的是最适合手机的竖屏。
// 横竖切换要换一块屏，UU 会丢掉选中的屏、跳回第一块，状态也跟着复杂，已经砍掉
import Foundation

public enum PhoneScreenSpec {
    /// 在「显示器」设置和 UU远程 的屏幕列表里看到的名字
    public static let name = "Snug 手机屏"
    /// 'SN'：认出自己建的屏
    public static let vendorID: UInt32 = 0x534E
    public static let productID: UInt32 = 0x00F0
    /// 底部小横条（点一下回到窗口列表）占的高度，放上来的窗口让出这一条
    public static let homeBarHeight = 28.0
    /// 建好不到这么久就释放会让 WindowServer 卡死（原作者实测）
    public static let minimumLifetime: TimeInterval = 2.5

    /// 逻辑尺寸（点）。按 UU 在 iPhone 17 Pro Max 上竖屏不被遮挡的区域定比例（底部 UU 工具栏约 268px），
    /// UU 按比例居中显示，比手机窄出来的部分正好落在被遮挡的地方。宽 540 是 2 倍高清的门槛：再窄，系统就只给 1 倍
    public static let width = 540
    public static let height = 950
    public static let pixelWidth = width * 2
    public static let pixelHeight = height * 2

    /// 物理尺寸按约 220ppi 折算。按手机的真实密度（460ppi）算，全新身份的屏永远不上线，
    /// 而且这个身份从此被系统「拉黑」，改回来也不行
    public static let millimeters = (width: Double(pixelWidth) / 220 * 25.4, height: Double(pixelHeight) / 220 * 25.4)

    /// 身份（序列号）：固定一个，建了不上线就依次换备用的。
    /// 固定身份能让系统记住这块屏的设置；每多用一个新身份，系统就多存一份 ICC 文件
    public static let serials: [UInt32] = [200_000_008, 200_000_018, 200_000_028]
}
