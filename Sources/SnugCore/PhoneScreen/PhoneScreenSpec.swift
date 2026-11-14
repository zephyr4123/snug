// 手机屏的身份与物理参数。尺寸和档位归屏幕适配（ScreenFit）。数值全部实测过（见记忆 project-phone-screen）。
// 只有竖屏一种：原版 UU 本来就是横屏，Snug 补的是最适合手机的竖屏。
// 横竖切换要换一块屏，UU 会丢掉选中的屏、跳回第一块，状态也跟着复杂，已经砍掉
import Foundation

public enum PhoneScreenSpec {
    /// 在「显示器」设置和 UU远程 的屏幕列表里看到的名字
    public static let name = "Snug 手机屏"
    /// 'SN'：认出自己建的屏
    public static let vendorID: UInt32 = 0x534E
    public static let productID: UInt32 = 0x00F0
    /// 建好不到这么久就释放会让 WindowServer 卡死（原作者实测）
    public static let minimumLifetime: TimeInterval = 2.5

    /// 物理尺寸按像素上限、约 220ppi 折算。按手机的真实密度（460ppi）算，全新身份的屏永远不上线，
    /// 而且这个身份从此被系统「拉黑」，改回来也不行
    public static let millimeters = (width: ScreenFit.maxPixels.width / 220 * 25.4, height: ScreenFit.maxPixels.height / 220 * 25.4)

    /// 身份（序列号）：固定一个，建了不上线就依次换备用的。
    /// 固定身份能让系统记住这块屏的设置；每多用一个新身份，系统就多存一份 ICC 文件。
    /// 有了多档以后换过一组：旧的那组被系统记成只有一档、像素上限也不同，不在旧身份上试新规格
    public static let serials: [UInt32] = [200_000_108, 200_000_118, 200_000_128]
}
