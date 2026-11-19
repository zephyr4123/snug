// 设备：类别、方向、屏幕数值，用户选的那一台（DeviceChoice）连同数值和类别一起存进配置。
// 纯值类型，配置、还原账、屏幕调度都用；从机型库里挑（见 DeviceCatalog），也可以自己填分辨率
import Foundation

/// 设备类别：行为只看它，不看屏的形状（iPhone Duo 内屏和 iPad Pro 11 形状几乎一样，一个是手机一个是平板）
public enum DeviceKind: String, Codable, CaseIterable, Sendable {
    case phone, tablet, computer
}

// 按类别定的几条规则只写在这里，全用 switch：加一个类别时编译器逐处报错，不会有哪处悄悄按老规矩走
extension DeviceKind {
    /// 触屏：屏上有 App 资源库面板，翻译手势、放大字号（见 ScreenPlan.behavior）；电脑都不要
    public var isTouch: Bool {
        switch self {
        case .phone, .tablet: true
        case .computer: false
        }
    }

    /// 平常的方向：添加屏幕时选了这一类先摆成它；名字里是这个方向就不写「横屏」「竖屏」（见 ScreenConfig.suggestedName）
    public var usualOrientation: Orientation {
        switch self {
        case .phone: .portrait
        case .tablet, .computer: .landscape
        }
    }

    /// 能选的方向：电脑只有横屏
    public var allowedOrientations: [Orientation] {
        switch self {
        case .phone, .tablet: [.portrait, .landscape]
        case .computer: [.landscape]
        }
    }

    /// 一块屏的型号能换成哪几类：触不触屏一样的才能换。屏上的面板、手势跟着触屏走，跨过去等于换一块屏
    public var swappableKinds: Set<DeviceKind> {
        Set(Self.allCases.filter { $0.isTouch == isTouch })
    }
}

/// 屏的方向：添加时定，之后不改（换方向要撤屏重建，UU 也得重选屏，和换一块新屏没有区别）
public enum Orientation: String, Codable, CaseIterable, Sendable {
    case portrait, landscape
}

/// 一台设备的屏幕，短边在前。手机、平板写面板的分辨率（像素），另有逻辑分辨率的短边（点）；
/// 手机只看比例，所以自己填的也可以是比例（9 × 20 和 1080 × 2400 一样）。
/// 电脑写系统设置「显示器」里用的那一档（点，如 MacBook Air 13 的 1470 × 956）：电脑屏照搬它，和本机看着一样大。
/// Mac 的缩放档不是面板像素的整数分之一（Air 15 是 2880 × 1864 显示成 1710 × 1112），从像素推不准，所以直接写点
public struct DeviceScreen: Codable, Hashable, Sendable {
    public var width: Int
    public var height: Int
    /// 手机、平板逻辑分辨率的短边（点）。Apple 设备有公开数值；不知道时按 ScreenFit 里的估值。电脑不用
    public var points: Int?
    /// 有刘海的 MacBook：刘海那一条的高度（点），横屏时扣掉
    public var notch: Int?

    public init(width: Int, height: Int, points: Int? = nil, notch: Int? = nil) {
        self.width = width
        self.height = height
        self.points = points
        self.notch = notch
    }

    /// 能用来算比例：都是正数，短边在前
    public var isValid: Bool {
        width > 0 && height > 0 && width <= height && (points ?? 1) > 0 && (notch ?? 0) >= 0
    }

    /// 机型库和配置都存短边在前，界面按屏幕方向显示、回填宽和高
    public func dimensions(in orientation: Orientation) -> (width: Int, height: Int) {
        orientation == .portrait ? (width, height) : (height, width)
    }

    /// 自己填的分辨率或比例：长短边填反了的换过来；没填、不是正数、大得离谱的不收
    public static func custom(_ a: Int?, _ b: Int?) -> DeviceScreen? {
        let range = 1...20000
        guard let a, let b, range.contains(a), range.contains(b) else { return nil }
        return DeviceScreen(width: min(a, b), height: max(a, b))
    }
}

/// 机型库里的一台
public struct DeviceModel: Hashable, Sendable, Identifiable {
    public let brand: String
    public let name: String
    public let kind: DeviceKind
    public let screen: DeviceScreen

    /// 品牌 + 型号，如「Apple iPhone 17 Pro Max」「华为 Mate 70 Pro」：选中后存进配置、显示在设置里的就是它
    public var id: String { "\(brand) \(name)" }
}

/// 用户选的设备：机型库里的一台，或自己填的分辨率和类别
public struct DeviceChoice: Codable, Equatable, Sendable {
    /// 机型全名（DeviceModel.id）；自己填的为 nil
    public var model: String?
    public var screen: DeviceScreen
    public var kind: DeviceKind

    public init(model: String?, screen: DeviceScreen, kind: DeviceKind = .phone) {
        self.model = model
        self.screen = screen
        self.kind = kind
    }

    public init(_ model: DeviceModel) {
        self.init(model: model.id, screen: model.screen, kind: model.kind)
    }

    private enum CodingKeys: String, CodingKey { case model, screen, kind }

    /// 2.5 以前存的手机型号没有 kind：都是手机
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        model = try c.decodeIfPresent(String.self, forKey: .model)
        screen = try c.decode(DeviceScreen.self, forKey: .screen)
        kind = (try? c.decodeIfPresent(DeviceKind.self, forKey: .kind)) ?? .phone
    }

    /// 没选过时用的：手机屏最早就是在这台上调出来的（540×950）。必须和机型库里的那一条一致（有测试盯着）
    public static let standard = DeviceChoice(model: "Apple iPhone 17 Pro Max", screen: DeviceScreen(width: 1320, height: 2868, points: 440))

    /// 显示用的名字：机型去掉品牌（「iPhone 17 Pro Max」），自己填的写分辨率
    public var title: String {
        guard let model else { return "\(screen.width) × \(screen.height)" }
        return model.hasPrefix("Apple ") ? String(model.dropFirst("Apple ".count)) : model
    }
}
