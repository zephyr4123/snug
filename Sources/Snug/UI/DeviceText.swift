// 设备和屏幕列表的显示文案：类别、方向、型号、分辨率怎么写，类别用哪个图标。设置窗口和屏上的型号页共用
import SnugCore

extension DeviceChoice {
    /// 名字：机型去掉 Apple，自己填的叫「自定义」（分辨率另外写，见 sizeText）
    var displayName: String { model == nil ? "自定义" : title }
    /// 自己填的分辨率：打开自定义输入时先填上它
    var customScreen: DeviceScreen? { model == nil ? screen : nil }
}

extension DeviceScreen {
    func sizeText(in orientation: Orientation) -> String {
        let size = dimensions(in: orientation)
        return "\(size.width) × \(size.height)"
    }
}

extension DeviceKind {
    var title: String {
        switch self {
        case .phone: "手机"
        case .tablet: "平板"
        case .computer: "电脑"
        }
    }

    /// 类别的图标（设置里的图标块、屏上的「型号」按钮）
    func symbol(_ orientation: Orientation) -> String {
        switch (self, orientation) {
        case (.phone, .portrait): "iphone"
        case (.phone, .landscape): "iphone.landscape"
        case (.tablet, .portrait): "ipad"
        case (.tablet, .landscape): "ipad.landscape"
        case (.computer, _): "laptopcomputer"
        }
    }
}

extension Orientation {
    var title: String { self == .portrait ? "竖" : "横" }

    /// 自定义输入的例子和这一方向上实际看到的宽、高一致
    var customHint: String {
        self == .portrait ? "屏幕分辨率或比例，如 1080 × 2400、9 × 20" : "屏幕分辨率或比例，如 2400 × 1080、20 × 9"
    }
}

extension ScreenConfig {
    /// 列表里名字下面那一行：「竖 · iPhone 17 Pro Max」
    var summary: String { "\(orientation.title) · \(device.displayName)" }
    var symbol: String { device.kind.symbol(orientation) }
    /// 屏上的点数（基准那一档）：「950 × 660 点」
    var sizeText: String {
        let fit = ScreenPlan.fit(of: self)
        let size = fit.size(width: fit.baseWidth)
        return "\(Int(size.width)) × \(Int(size.height)) 点"
    }

    /// 分辨率能调的屏（手机、平板）才有
    var resolution: ScreenResolution? { ScreenResolution(device: device, orientation: orientation) }
    /// 用的是不是默认档：存的值夹回范围后落在默认档也算（机型库改了数值、手改了配置），和调整界面一个判法
    var usesDefaultResolution: Bool { resolution.map { $0.width(stored: baseWidth) == $0.range.lowerBound } ?? true }
    /// 屏幕详情、型号页上分辨率的值：默认写「默认」，调过写点数
    var resolutionText: String { usesDefaultResolution ? "默认" : sizeText }
}

extension ScreenResolution {
    /// 这一档的点数：「1180 × 820 点」
    func sizeText(_ width: Int) -> String {
        let size = size(width: width)
        return "\(Int(size.width)) × \(Int(size.height)) 点"
    }

    /// 调整界面的读数：默认档后面写明「（默认）」
    func readout(_ width: Int) -> String {
        sizeText(width) + (width == range.lowerBound ? "（默认）" : "")
    }
}

extension ScreenResolution.Clarity {
    /// 调整时预览下面那一行
    var text: String {
        switch self {
        case .soft(let percent): "画面略软 · 像素为屏幕的 \(percent)%"
        case .sharpest: "最清晰 · 像素与屏幕一致"
        case .beyond: "最清晰 · 再往右只增加空间"
        }
    }

    /// 型号页那一行的短说法
    var short: String {
        if case .soft = self { "画面略软" } else { "最清晰" }
    }

    var isSharp: Bool {
        if case .soft = self { false } else { true }
    }

    /// 读数下面那行的图标：清晰打勾，略软半个圆
    var symbol: String { isSharp ? "checkmark.circle.fill" : "circle.lefthalf.filled" }
}
