// 一块屏此刻该在，以及它该是什么样：ScreenPlan 按配置和会话算出来交给 DeskSet，
// ScreenSet 按身份和比例建撤、在线换比例，Desk 按行为参数放窗口。
// 谁也不认手机、平板、电脑：类别到行为的映射只在 ScreenPlan 里（见 docs/development.md「代码结构」）
import CoreGraphics
import Foundation

/// 屏的身份：系统按 vendorID + productID + 序列号记住一块屏的设置、排布和 ICC 文件。
/// 数值全部实测过（见记忆 project-phone-screen、project-multi-screen）
public struct ScreenSpec: Equatable, Sendable {
    /// 'SN'：认出自己建的屏
    public static let vendorID: UInt32 = 0x534E
    /// 竖屏、横屏的产品号：竖屏沿用 2.5 以前手机屏的 0x00F0，横屏另起 0x00F1
    public static let portraitProductID: UInt32 = 0x00F0
    public static let landscapeProductID: UInt32 = 0x00F1
    /// 建好不到这么久就释放会让 WindowServer 卡死（原作者实测）
    public static let minimumLifetime: TimeInterval = 2.5

    /// 在「显示器」设置和远控的屏幕列表里看到的名字（UU 列成「显示屏 N (名字)」）
    public var name: String
    /// 竖屏 0x00F0（2.5 以前的手机屏就是它），横屏 0x00F1
    public var productID: UInt32
    /// 序列号：固定一个，建了不上线就依次换备用的。固定身份能让系统记住这块屏的设置；每多用一个新身份，系统就多存一份 ICC 文件。
    /// 号码添加时分配、永不复用，免得系统把旧屏的记忆套到新屏上
    public var serials: [UInt32]
    /// 像素上限，框住这块屏的所有档位；必须和屏的方向一致（横屏上限的屏上，竖着的档不能用，V4）
    public var maxPixels: CGSize

    public init(name: String, productID: UInt32, serials: [UInt32], maxPixels: CGSize) {
        self.name = name
        self.productID = productID
        self.serials = serials
        self.maxPixels = maxPixels
    }

    /// 物理尺寸按像素上限、约 220ppi 折算。按设备的真实密度（手机 460ppi）算，全新身份的屏永远不上线，
    /// 而且这个身份从此被系统「拉黑」，改回来也不行
    public var millimeters: CGSize {
        CGSize(width: maxPixels.width / 220 * 25.4, height: maxPixels.height / 220 * 25.4)
    }
}

/// 一块屏上的行为，ScreenPlan 按型号的类别给；下游只认它，不认类别
public struct ScreenBehavior: Equatable, Sendable {
    /// 触屏用的屏（手机、平板）：屏上有 App 资源库和小横条，翻译手势（设置里开着时），放上来的窗口铺满整块屏、
    /// 按窗口换档、放大字号。电脑屏用左侧切换器或菜单栏资源库，窗口只挪过来，大小、字号不动
    public var touch: Bool

    public init(touch: Bool) {
        self.touch = touch
    }

    public static let touchScreen = ScreenBehavior(touch: true)
    public static let computer = ScreenBehavior(touch: false)
}

public struct ScreenWish: Equatable, Sendable {
    public let id: ScreenID
    public var spec: ScreenSpec
    public var fit: ScreenFit
    public var behavior: ScreenBehavior
    /// 建好后设为主屏、撤之前设回原来的主屏（最多一块，见 docs/how-it-works.md「设为主屏」）
    public var main: Bool
    /// 提前准备的屏（设置里「提前准备虚拟屏」）：没人远程也在，给只在启动时认屏的远控
    public var prepared: Bool
    /// 在手机上退出时只还原窗口、屏留着（见 DeskSet.dismissScreen）
    public var staysOnDismiss: Bool

    public init(id: ScreenID, spec: ScreenSpec, fit: ScreenFit, behavior: ScreenBehavior, main: Bool = false, prepared: Bool = false) {
        self.id = id
        self.spec = spec
        self.fit = fit
        self.behavior = behavior
        self.main = main
        self.prepared = prepared
        staysOnDismiss = false
    }

    /// 常驻、不随远程建撤：设为主屏的那块，和提前准备的屏
    public var resident: Bool { main || prepared }
}
