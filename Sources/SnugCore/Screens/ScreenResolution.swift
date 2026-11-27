// 分辨率：手机、平板屏的基准宽度可以调宽（屏幕详情、屏上型号页的「分辨率」），画面更细、字更小、装得更多（#54、#66）。
// 范围是默认档到默认的最宽一档（默认的 2 倍、不超过像素上限），和 ScreenFit 登记的档位一致，建屏时照它夹。
// 屏都是 2 倍渲染，推出去的像素 = 点数 × 2：比控制端屏幕的像素少时，控制端要放大显示，画面略软；
// 「最清晰」是 2 倍像素正好等于屏幕像素的那一档，再往右只多装内容，不会更细。电脑屏照搬电脑自己的分辨率，不调。
// 选的值存在 ScreenConfig.baseWidth（默认存 nil），换型号时回到默认
import CoreGraphics

public struct ScreenResolution: Hashable, Sendable {
    /// 能选的基准宽度（点）：默认档到默认的最宽一档
    public let range: ClosedRange<Int>
    /// 「最清晰」那一档：比默认宽、又在范围里时才有（默认就够清晰、或屏幕像素多到够不着时没有）
    public let sharpest: Int?
    /// 控制端屏幕在这块屏宽度方向上的像素。自己填的是比例（9 × 20）、或比默认档还少时不认：不知道屏幕有多少像素，不报清晰度
    let pixels: Int?
    let ratio: Double

    public enum Clarity: Hashable, Sendable {
        /// 像素比屏幕少：控制端放大显示，略软。percent 向下取整，差一点也不报 100
        case soft(percent: Int)
        /// 像素和屏幕一样多
        case sharpest
        /// 比屏幕还多：一样清晰，只是装得更多
        case beyond
    }

    /// 电脑屏没有（nil）
    public init?(device: DeviceChoice, orientation: Orientation) {
        guard device.kind.isTouch else { return nil }
        let standard = ScreenFit(device: device.screen, kind: device.kind, orientation: orientation)
        range = standard.baseWidth...(standard.widths.last ?? standard.baseWidth)
        ratio = standard.ratio
        let across = Self.pixelsAcross(device.screen, kind: device.kind, orientation: orientation)
        let half = across / 2
        pixels = half >= range.lowerBound ? across : nil
        sharpest = (range.lowerBound + 1...range.upperBound).contains(half) ? half : nil
    }

    /// 这一档的逻辑尺寸（点）：和 ScreenFit 的一样
    public func size(width: Int) -> CGSize {
        CGSize(width: CGFloat(width), height: (Double(width) * ratio).rounded())
    }

    /// 选这一档时的清晰度；不知道屏幕像素时为 nil
    public func clarity(at width: Int) -> Clarity? {
        guard let pixels else { return nil }
        // 屏幕像素是奇数时，最清晰那一档的 2 倍比它少 1：也算一样多
        let doubled = width * 2
        if abs(doubled - pixels) <= 1 { return .sharpest }
        return doubled < pixels ? .soft(percent: doubled * 100 / pixels) : .beyond
    }

    /// 滑块的值 → 一档：从默认档起每 ScreenFit.step 点一格，和建屏登记的档位对齐；靠近最清晰时吸到那一格，两头够得着
    public func snapped(_ value: Double) -> Int {
        let step = Double(ScreenFit.step)
        if let sharpest, abs(value - Double(sharpest)) <= step { return sharpest }
        if value >= Double(range.upperBound) - step / 2 { return range.upperBound }
        let lower = range.lowerBound
        return (lower + Int(((value - Double(lower)) / step).rounded()) * ScreenFit.step).clamped(to: range)
    }

    /// 存进配置的值：默认档存 nil（换了机型库数值也跟着默认走）
    public func stored(_ width: Int) -> Int? {
        width == range.lowerBound ? nil : width
    }

    /// 配置里存的值 → 这一档：机型库改了数值、手改了配置时夹回范围
    public func width(stored: Int?) -> Int {
        (stored ?? range.lowerBound).clamped(to: range)
    }

    /// 控制端屏幕在这块屏宽度方向上的像素：远控把画面按宽度铺满时，宽度方向上能用的那些像素
    /// （手机横屏扣掉远控左右让出的部分，换算成像素；竖屏的上下让位不影响宽度）
    private static func pixelsAcross(_ screen: DeviceScreen, kind: DeviceKind, orientation: Orientation) -> Int {
        let short = Double(screen.width), long = Double(screen.height)
        switch (kind, orientation) {
        case (_, .portrait):
            return screen.width
        case (.phone, .landscape):
            let points = screen.points.map(Double.init) ?? ScreenFit.assumedPhonePoints
            return Int((long - ScreenFit.clientLandscapeInsets * short / points).rounded())
        case (_, .landscape):
            return screen.height
        }
    }
}
