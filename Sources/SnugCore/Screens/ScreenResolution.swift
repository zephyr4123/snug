// 分辨率：手机、平板屏的基准宽度可以调宽（屏幕详情、屏上型号页的「分辨率」），画面更细、字更小、装得更多（#54、#66）。
// 范围取自默认 ScreenFit 登记的档位（默认档到最宽一档：默认的 2 倍、不超过像素上限）。ScreenFit 是唯一的真相源，
// 建屏时由它夹选中的宽度，这里只读它。
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
    /// 默认那一档的 ScreenFit：比例、档位都从它取
    private let standard: ScreenFit

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
        self.standard = standard
        range = standard.baseWidth...(standard.widths.last ?? standard.baseWidth)
        // 远控把画面等比铺满控制端屏幕：竖屏撑满宽，横屏撑满高（短边），宽度方向用到的像素按这块屏的比例从短边换算
        let across = orientation == .portrait ? device.screen.width : Int((Double(device.screen.width) / standard.ratio).rounded())
        let half = across / 2
        pixels = half >= range.lowerBound ? across : nil
        sharpest = range.lowerBound < half && half <= range.upperBound ? half : nil
    }

    /// 这一档的逻辑尺寸（点）
    public func size(width: Int) -> CGSize { standard.size(width: width) }

    /// 选这一档时的清晰度；不知道屏幕像素时为 nil
    public func clarity(at width: Int) -> Clarity? {
        guard let pixels else { return nil }
        // 屏幕像素是奇数时，最清晰那一档的 2 倍比它少 1：也算一样多
        let doubled = width * 2
        if abs(doubled - pixels) <= 1 { return .sharpest }
        return doubled < pixels ? .soft(percent: doubled * 100 / pixels) : .beyond
    }

    /// 滑块的值 → 一档：从默认档起每 ScreenFit.step 点一格，和建屏登记的档位对齐；靠近最清晰时吸到那一格。
    /// 拖到头就是头（最清晰紧挨着头时也够得着）；吸出来的值再吸一次不变（屏上开始滑动时先按现在的值吸一次）
    public func snapped(_ value: Double) -> Int {
        let lower = range.lowerBound, step = Double(ScreenFit.step)
        if value <= Double(lower) { return lower }
        if value >= Double(range.upperBound) { return range.upperBound }
        let grid = (lower + Int(((value - Double(lower)) / step).rounded()) * ScreenFit.step).clamped(to: range)
        // 落进最清晰左右一格以内的格子不单独给：吸过去，免得两格挨着、再吸一次就跳
        if let sharpest, abs(value - Double(sharpest)) < step || abs(grid - sharpest) < ScreenFit.step { return sharpest }
        return grid
    }

    /// 往大或往小挪一格（无障碍的加减）：相邻那格被最清晰吸回原地时，再多挪一格
    public func stepped(_ width: Int, up: Bool) -> Int {
        let step = Double(up ? ScreenFit.step : -ScreenFit.step)
        let next = snapped(Double(width) + step)
        return next != width ? next : snapped(Double(width) + 2 * step)
    }

    /// 存进配置的值：默认档存 nil（换了机型库数值也跟着默认走）
    public func stored(_ width: Int) -> Int? {
        width == range.lowerBound ? nil : width
    }

    /// 配置里存的值 → 这一档：机型库改了数值、手改了配置时夹回范围
    public func width(stored: Int?) -> Int {
        (stored ?? range.lowerBound).clamped(to: range)
    }

}
