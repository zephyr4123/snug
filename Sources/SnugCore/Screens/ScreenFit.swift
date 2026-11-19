// 屏幕适配：屏的比例跟着型号、方向和类别走，宽度跟着屏上的窗口走（docs/how-it-works.md「屏幕适配」）。
// 比例：把型号的屏幕按这块屏的方向摆好，扣掉 UU 在这个方向上压住画面的部分：
// - 手机竖屏：UU 把画面等比缩放、居中铺在手机上，上下压掉 uuInset（17 Pro Max 上是 540×950，真机调出来的）
// - 手机横屏：UU 的工具栏在右边压一条，左边（灵动岛那侧）压一条暗带，上下不压（V6，11-17 主人定扣左右）
// - 平板：UU 铺满、不压，横竖都不扣（V6）
// - 电脑：UU 全屏时等比缩小、四周留黑边，不挡东西；有刘海的 MacBook 扣掉顶上那一条，画面正好一像素对一像素（V6）
// 宽度：平时用基准宽度。2 倍高清的门槛按屏自己的方向算，长边 ≥ 800、短边 ≥ 525 点（V4）；
// 手机竖屏沿用 540 宽（2.8：降到 525 字只大约 3%，老用户升级后无感更要紧），手机横屏取门槛里最窄的一档（字最大），
// 平板按 V10 的体感取逻辑分辨率除以 1.24，电脑取它自己的分辨率（超出像素上限的按上限，字大一点）。
// App 限定了最小尺寸、基准宽度铺不满时，屏换成刚好装得下它的一档，窗口照样铺满，整屏等比缩小（手机上可以双指放大）。
// 档位建屏时一次登记好，宽高比都一样：换档时 UU 不用重新推流、点击位置照样准，画面平滑缩放；
// 换档只是选一档（帮手进程切，约 0.4 秒，屏不掉线、编号不变）。同一块屏上不登记相差太大的档（V4），最宽到基准的 2 倍
import CoreGraphics

public struct ScreenFit: Equatable, Sendable, CustomStringConvertible {
    /// Snug 自己的面板和手势阈值按这个短边设计（17 Pro Max 竖屏的基准宽度）
    public static let designWidth = 540
    /// 2 倍高清的门槛（实测，和像素上限无关）：长边不小于 800、短边不小于 525 点，系统才把 2 倍模式标成桌面可用
    public static let minLongSide = 800
    public static let minShortSide = 525
    /// 手机竖屏的最窄一档：沿用 2.5 以前的 540
    public static let minPhoneWidth = 540
    /// 相邻两档差 10 点：装下窗口后最多多缩 2%
    public static let step = 10
    /// 竖屏高宽比的范围：最方到正方形（折叠屏内屏扣掉工具栏后比这还方），最长到 2（像素上限按它定）
    public static let portraitRatios: ClosedRange<Double> = 1...2
    /// 像素上限：竖屏框住 1080 宽、比例 2 的最宽一档（和 2.5 以前一样，换比例时屏幕身份不变、不多出 ICC 文件）；
    /// 横屏框得住 6K 的 3008×1692 的 2 倍（V5：新身份当场上线）
    public static let portraitPixels = CGSize(width: 2160, height: 4320)
    public static let landscapePixels = CGSize(width: 6144, height: 3840)
    /// 横屏最宽到 24:5。第一档登记最宽尺寸，按已有的上线余量保留至少三分之一的像素高度（见 registrationOrder）。
    public static let landscapeRatios: ClosedRange<Double> = (landscapePixels.height / 3 / landscapePixels.width)...1
    /// 手机竖屏画面上下各让出的高度（点）。UU 底部工具栏 17 Pro Max 实测约 268 像素（89 点）；取 91 让 17 Pro Max 正好是
    /// 真机上调好的 540×950（取 89 是 540×955），多出的 2 点当余量
    static let uuInset: Double = 91
    /// 手机横屏左右让出的宽度（手机的点）：右边 UU 的工具栏约 82，左边（灵动岛那侧）的暗带约 72（V6 第一轮实测粗估，待截图量准）
    static let uuLandscapeInsets: Double = 82 + 72
    /// 不知道逻辑分辨率时（安卓、自己填的）按这个估短边：安卓手机默认显示大小下常见 360–412dp，平板 800dp 上下
    static let assumedPhonePoints: Double = 400
    static let assumedTabletPoints: Double = 800
    /// 1 个 Mac 点约合 1.24 个平板点：V10 在 iPad 上的体感，字大、看着舒服
    static let tabletScale: Double = 1.24
    /// 设计短边 540 点时底部小横条的高度。平板按短边放大界面时，让窗口多留一点纵向空间。
    public enum HomeBarStyle: CGFloat, Sendable {
        case phone = 28
        case tablet = 22
        case hidden = 0
    }

    public private(set) var homeBarStyle = HomeBarStyle.phone

    /// 高宽比
    public let ratio: Double
    /// 基准宽度：App 资源库、能铺满的窗口都用它
    public let baseWidth: Int
    /// 登记的档位：从基准宽度起每 10 点一档，像素上限截断最后一步时也登记上限
    public let widths: [Int]

    /// 登记给系统时的顺序：最宽的在前。系统按第一档判断这块屏能不能上线，第一档比像素上限小太多时屏建好了却一直不上线
    /// （11-17 实测：上限 6144×3840 时，2 倍高 1050 像素的不上线、1120 的上线）。手机横屏的基准档 957×525 就是这样；
    /// 最宽一档在前当场上线，窄的档照样列出、能切
    public var registrationOrder: [Int] { widths.reversed() }

    /// 没选过型号时的比例（17 Pro Max 竖屏，540×950）
    public static let standard = ScreenFit(device: DeviceChoice.standard.screen, kind: .phone, orientation: .portrait)

    /// 按型号、类别和这块屏的方向算
    public init(device: DeviceScreen, kind: DeviceKind, orientation: Orientation) {
        let short = Double(device.width), long = Double(device.height)
        switch (kind, orientation) {
        case (.phone, .portrait):
            let points = device.points.map(Double.init) ?? Self.assumedPhonePoints
            self.init(ratio: long / short - 2 * Self.uuInset / points)
        case (.phone, .landscape):
            let points = device.points.map(Double.init) ?? Self.assumedPhonePoints
            self.init(ratio: points / (long * points / short - Self.uuLandscapeInsets), orientation: .landscape, width: nil)
        case (.tablet, _):
            let points = device.points.map(Double.init) ?? Self.assumedTabletPoints
            let across = orientation == .portrait ? points : long * points / short
            let ratio = orientation == .portrait ? long / short : short / long
            self.init(ratio: ratio, orientation: orientation, width: Int((across / Self.tabletScale).rounded()))
        case (.computer, .landscape):
            // 电脑的分辨率本来就是点（系统设置「显示器」里的那一档），照搬，和它本机看着一样大
            self.init(ratio: (short - Double(device.notch ?? 0)) / long, orientation: .landscape, width: device.height)
        case (.computer, .portrait):
            self.init(ratio: long / short, orientation: .portrait, width: device.width)
        }
        homeBarStyle = switch kind {
        case .phone: .phone
        case .tablet: .tablet
        case .computer: .hidden
        }
    }

    /// 手机竖屏：2.5 以前的算法，一点不变
    init(ratio: Double) {
        let ratio = ratio.clamped(to: Self.portraitRatios)
        self.ratio = ratio
        // 矮的屏 540 宽时高不到 800，没有 2 倍：基准加宽到够高的最窄一档（比例不小于 1，800 宽一定够）
        let maxWidth = Int(Self.portraitPixels.width) / 2
        let all = stride(from: Self.minPhoneWidth, through: maxWidth, by: Self.step)
        baseWidth = all.first { (Double($0) * ratio).rounded() >= Double(Self.minLongSide) } ?? maxWidth
        widths = Array(stride(from: baseWidth, through: maxWidth, by: Self.step))
    }

    /// 别的屏：width 是想要的基准宽度（nil 就取门槛里最窄的一档），不够 2 倍门槛就加宽到够；最宽到基准的 2 倍，不超过像素上限
    init(ratio: Double, orientation: Orientation, width wanted: Int?) {
        let ratio = ratio.clamped(to: orientation == .portrait ? Self.portraitRatios : Self.landscapeRatios)
        self.ratio = ratio
        let pixels = orientation == .portrait ? Self.portraitPixels : Self.landscapePixels
        // 像素上限给的最宽一档：宽、高的 2 倍都要框得住
        let limit = Int(min(pixels.width / 2, (pixels.height / 2 / ratio).rounded(.down)))
        // 2 倍门槛：竖屏宽 ≥ 525、高 ≥ 800，横屏宽 ≥ 800、高 ≥ 525（高 = 宽 × 比例，四舍五入）
        let (minWidth, minHeight) = orientation == .portrait ? (Self.minShortSide, Self.minLongSide) : (Self.minLongSide, Self.minShortSide)
        let threshold = max(minWidth, Int(((Double(minHeight) - 0.5) / ratio).rounded(.up)))
        let base = min(max(wanted ?? threshold, threshold), limit)
        baseWidth = base
        var steps = Array(stride(from: base, through: min(base * 2, limit), by: Self.step))
        // 到像素上限时也把最后不足 10 点的一步走完，否则最宽的横屏可能差一两点才够登记高度。
        if limit <= base * 2, steps.last != limit { steps.append(limit) }
        widths = steps
    }

    /// 这一档的逻辑尺寸（点）
    public func size(width: Int) -> CGSize {
        CGSize(width: CGFloat(width), height: (Double(width) * ratio).rounded())
    }

    /// 日志里的样子：基准尺寸
    public var description: String {
        "\(baseWidth)×\(Int(size(width: baseWidth).height))"
    }

    /// 窗口该用哪一档。window 是按 area（current 这一档的可放区域）铺过之后读回的实际大小：
    /// 装得下就还是 current；App 不让缩到那么小，就按超出的比例往上找装得下的最窄一档，超过最宽一档就用最宽一档。
    /// 按比例放大是够的：可放区域里只有菜单栏不跟着缩放，屏越宽它占的比例越小。
    /// 先乘后除：540 × (580 / 540) 在浮点下是 580.0000000000001，向上取整会多进一档
    public func width(toFit window: CGSize, in area: CGSize, at current: Int) -> Int {
        let tolerance: CGFloat = 2
        guard window.width > area.width + tolerance || window.height > area.height + tolerance else { return current }
        let base = CGFloat(current)
        let needed = max(base * window.width / area.width, base * window.height / area.height)
        return widths.first { CGFloat($0) >= needed.rounded(.up) } ?? widths.last ?? current
    }

    /// 屏上的点比设计尺寸大了几倍：Snug 自己的面板和手势阈值按它放大，在手机上看着、划着一样大。
    /// 按短边算：手机竖屏是宽，横屏是高，横竖拿着一个点在手机上一样大；平板按 V10 的体感，660 宽时是 1.22 倍
    public static func scale(screen: CGSize) -> CGFloat {
        min(screen.width, screen.height) / CGFloat(designWidth)
    }

    /// 底部小横条的高度（这一档的点）：跟着缩放，手指点着一样大。放上来的窗口让出这一条
    public static func homeBarHeight(screen: CGSize, style: HomeBarStyle = .phone) -> CGFloat {
        (style.rawValue * scale(screen: screen)).rounded()
    }
}

extension TouchRegion {
    /// 手势翻译管整块屏，阈值按这一档比设计尺寸大几倍放大（和小横条一样，在手机上划着手感不变）。
    /// closeButton：屏上那个窗口的关闭按钮，点它时交给 Snug 先放回原位再关
    public init(screen bounds: CGRect, closeButton: CloseButton? = nil) {
        self.init(frame: bounds, scale: ScreenFit.scale(screen: bounds.size), closeButton: closeButton)
    }
}
