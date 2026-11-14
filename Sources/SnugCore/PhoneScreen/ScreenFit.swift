// 屏幕适配：手机屏的宽度跟着屏上的窗口走。
// 平时 540×950：短边 540 是 2 倍高清的门槛，再窄系统只给 1 倍。App 限定了最小尺寸、540 宽铺不满时，
// 手机屏换成刚好装得下它的一档，窗口照样铺满，整屏等比缩小（字跟着小，手机上可以双指放大）。
// 不按 App 预设：放窗口时先按 540 铺，App 卡在自己的最小尺寸上，读回来的大小就是它要的，据此选档。
// 档位建屏时一次登记好，宽高比都和 540×950 一样：换档时 UU 不用重新推流、点击位置照样准，画面平滑缩放；
// 换档只是选一档（帮手进程切，约 0.4 秒，屏不掉线、编号不变）。实测见记忆 project-phone-screen
import CoreGraphics

public enum ScreenFit {
    /// 基准宽度：窗口列表、能铺满的窗口都用它
    public static let baseWidth = 540
    /// 最宽一档：字只剩一半，不比 UU 原版看主屏大了，再宽没有意义。更宽的 App 用这一档、靠左放
    public static let maxWidth = 1080
    /// 相邻两档差 10 点：装下窗口后最多多缩 2%
    public static let step = 10
    public static let widths = Array(stride(from: baseWidth, through: maxWidth, by: step))
    /// 基准宽度下底部小横条的高度（点）
    static let baseHomeBarHeight: CGFloat = 28

    /// 这一档的逻辑尺寸（点）：高按 540×950 的比例
    public static func size(width: Int) -> CGSize {
        CGSize(width: CGFloat(width), height: (CGFloat(width) * 950 / CGFloat(baseWidth)).rounded())
    }

    /// 虚拟屏的像素上限：最宽一档的 2 倍
    public static var maxPixels: CGSize {
        let size = size(width: maxWidth)
        return CGSize(width: size.width * 2, height: size.height * 2)
    }

    /// 屏上的点比基准小了几倍：Snug 自己的面板按它放大，在手机上看着一样大
    public static func scale(screenWidth: CGFloat) -> CGFloat {
        screenWidth / CGFloat(baseWidth)
    }

    /// 底部小横条的高度（这一档的点）：跟着缩放，手指点着一样大。放上来的窗口让出这一条
    public static func homeBarHeight(screenWidth: CGFloat) -> CGFloat {
        (baseHomeBarHeight * scale(screenWidth: screenWidth)).rounded()
    }

    /// 窗口该用哪一档。window 是按 area（current 这一档的可放区域）铺过之后读回的实际大小：
    /// 装得下就还是 current；App 不让缩到那么小，就按超出的比例往上找装得下的最窄一档，超过最宽一档就用最宽一档。
    /// 按比例放大是够的：可放区域里只有菜单栏不跟着缩放，屏越宽它占的比例越小
    public static func width(toFit window: CGSize, in area: CGSize, at current: Int) -> Int {
        let tolerance: CGFloat = 2
        guard window.width > area.width + tolerance || window.height > area.height + tolerance else { return current }
        let needed = CGFloat(current) * max(window.width / area.width, window.height / area.height)
        return widths.first { CGFloat($0) >= needed.rounded(.up) } ?? maxWidth
    }
}
