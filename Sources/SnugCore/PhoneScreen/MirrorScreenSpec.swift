// 内建屏镜像：一块和内建屏同尺寸的横屏虚拟屏，内建屏镜像到它上面。
// 方向不能反过来：macOS 只把镜像组的主屏交给 ScreenCaptureKit，从屏在 NSScreen 和 ScreenCaptureKit 里都看不到，
// UU远程 的屏幕列表里就没有它。主屏是这块虚拟屏时，ScreenCaptureKit 只列出它，内建屏仍是 2 倍（macOS 27.2 实测）。
import CoreGraphics
import Foundation

public enum MirrorScreenSpec {
    /// 在「显示器」设置和 UU远程 的屏幕列表里看到的名字
    public static let name = "Snug 内建屏"
    /// 'SN'：和手机屏同一个厂商标识，产品号区分
    public static let vendorID: UInt32 = 0x534E
    public static let productID: UInt32 = 0x00F1
    /// 建好不到这么久就释放会让 WindowServer 卡死（和手机屏同一个经验值）
    public static let minimumLifetime: TimeInterval = 2.5

    /// 身份（序列号）：固定一个，建了不上线就依次换备用的。和手机屏的身份分开，
    /// 免得系统把两块屏记成同一块、或者把手机屏的档位记忆套到镜像屏上
    public static let serials: [UInt32] = [200_000_208, 200_000_218, 200_000_228]

    /// 虚拟屏的像素尺寸：内建屏的点尺寸乘它的缩放倍率。镜像组要求两边有共同的模式，
    /// 虚拟屏只有 1 倍时 macOS 会把内建屏也拉到 1 倍（实测），所以这里必须按真实倍率算
    public static func pixelSize(pointSize: CGSize, scale: CGFloat) -> CGSize {
        let scale = max(1, scale)
        return CGSize(width: (pointSize.width * scale).rounded(), height: (pointSize.height * scale).rounded())
    }

    /// 物理尺寸按像素上限、约 220ppi 折算。和手机屏同一套经验值：按真实密度算，全新身份的屏永远不上线
    public static func millimeters(pointSize: CGSize, scale: CGFloat) -> CGSize {
        let pixels = pixelSize(pointSize: pointSize, scale: scale)
        return CGSize(width: pixels.width / 220 * 25.4, height: pixels.height / 220 * 25.4)
    }
}
