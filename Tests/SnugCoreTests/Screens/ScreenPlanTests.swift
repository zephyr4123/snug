import Testing
@testable import SnugCore

@Suite("策略 ScreenPlan")
struct ScreenPlanTests {
    private let ipad = DeviceChoice(model: "Apple iPad（A16）", screen: DeviceScreen(width: 1640, height: 2360, points: 820), kind: .tablet)
    private let air = DeviceChoice(model: "Apple MacBook Air 13 英寸（M4）", screen: DeviceScreen(width: 956, height: 1470, notch: 33), kind: .computer)
    private let remote = true

    /// 手机竖屏 + iPad 横屏 + 关着的 Air
    private func config() -> AppConfig {
        var c = AppConfig()
        c.addScreen(orientation: .landscape, device: ipad)
        var off = c.addScreen(orientation: .landscape, device: air)!
        off.enabled = false
        c.screens[2] = off
        return c
    }

    @Test("远程中（含重连等待期）：建出所有开着的屏，按列表顺序；关着的不建")
    func enabledScreens() {
        let c = config()
        let wishes = ScreenPlan.wishes(config: c, remote: remote, trusted: true)
        #expect(wishes.map(\.id) == [.phone, c.screens[1].id])
        #expect(wishes[0].spec == ScreenPlan.spec(of: c.screens[0]))
        #expect(wishes[1].fit == ScreenPlan.fit(of: c.screens[1]))
    }

    @Test("不在远程（没设主屏）、没有辅助功能权限：一块都不要；预览模式不等远程")
    func gates() {
        let c = config()
        #expect(ScreenPlan.wishes(config: c, remote: false, trusted: true).isEmpty)
        #expect(ScreenPlan.wishes(config: c, remote: remote, trusted: false).isEmpty)
        #expect(ScreenPlan.wishes(config: c, remote: false, trusted: true, preview: true).count == 2)
        #expect(ScreenPlan.wishes(config: c, remote: false, trusted: false, preview: true).isEmpty)
    }

    @Test("类别 → 行为：手机、平板是触屏，电脑不是；手势总开关不改行为（翻不翻译由界面层按开关定）")
    func behavior() {
        #expect(ScreenPlan.behavior(.phone) == .touchScreen)
        #expect(ScreenPlan.behavior(.tablet) == .touchScreen)
        #expect(ScreenPlan.behavior(.computer) == .computer)
        var c = config()
        c.screens[2].enabled = true
        let on = ScreenPlan.wishes(config: c, remote: remote, trusted: true)
        c.gestures = false
        #expect(ScreenPlan.wishes(config: c, remote: remote, trusted: true) == on)
        #expect(on.map(\.behavior.touch) == [true, true, false])
    }

    @Test("身份按方向：竖屏 0xF0、横屏 0xF1，像素上限跟着方向；迁移来的那块沿用老身份")
    func identity() {
        let c = config()
        let wishes = ScreenPlan.wishes(config: c, remote: remote, trusted: true)
        #expect(wishes[0].spec.productID == ScreenSpec.portraitProductID)
        #expect(wishes[0].spec.maxPixels == ScreenFit.portraitPixels)
        #expect(wishes[0].spec.serials == [200_000_108, 200_000_118, 200_000_128])
        #expect(wishes[0].spec.name == "Snug 手机屏")
        #expect(wishes[1].spec.productID == ScreenSpec.landscapeProductID)
        #expect(wishes[1].spec.maxPixels == ScreenFit.landscapePixels)
    }

    @Test("设为主屏的那块标出来，最多一块")
    func main() {
        var c = config()
        c.mainScreen = c.screens[1].id
        let wishes = ScreenPlan.wishes(config: c, remote: remote, trusted: true)
        #expect(wishes.map(\.main) == [false, true])
    }

    @Test("设为主屏的那块常驻：不在远程也要它，别的屏照旧只在远程时要；关着、没有辅助功能权限时不要")
    func persistentMain() {
        var c = config()
        c.mainScreen = c.screens[1].id
        let idle = ScreenPlan.wishes(config: c, remote: false, trusted: true)
        #expect(idle.map(\.id) == [c.screens[1].id])
        #expect(idle.map(\.main) == [true])
        #expect(ScreenPlan.wishes(config: c, remote: false, trusted: false).isEmpty)
        c.screens[1].enabled = false
        #expect(ScreenPlan.wishes(config: c, remote: false, trusted: true).isEmpty)
    }

    @Test("加到上限就不再加；手改配置开了更多块：只建前 4 块")
    func limit() {
        var c = AppConfig()
        for _ in 1..<ScreenConfig.limit { #expect(c.addScreen(orientation: .portrait, device: .standard) != nil) }
        #expect(c.addScreen(orientation: .portrait, device: .standard) == nil)
        c.screens.append(ScreenConfig(id: .make(), orientation: .portrait, device: .standard, enabled: true, name: "手改的", serials: [1]))
        #expect(ScreenPlan.wishes(config: c, remote: remote, trusted: true).count == ScreenConfig.limit)
    }
}

@Suite("屏幕列表 ScreenConfig")
struct ScreenConfigTests {
    @Test("按型号起名：去掉代际和尺寸；每类设备平常的方向不加后缀，反过来的写明横竖；自己填的、通用分辨率按类别叫")
    func suggestedName() {
        func name(_ model: String?, _ kind: DeviceKind, _ o: Orientation) -> String {
            ScreenConfig.suggestedName(for: DeviceChoice(model: model, screen: DeviceScreen(width: 9, height: 20), kind: kind), orientation: o)
        }
        #expect(name("Apple iPhone 17 Pro Max", .phone, .portrait) == "Snug iPhone 17 Pro Max")
        #expect(name("Apple iPhone 17 Pro Max", .phone, .landscape) == "Snug iPhone 17 Pro Max 横屏")
        #expect(name("Apple iPad（第 10 代）", .tablet, .landscape) == "Snug iPad")
        #expect(name("Apple iPad Pro 11 英寸（M5）", .tablet, .portrait) == "Snug iPad Pro 竖屏")
        #expect(name("Apple MacBook Air 13 英寸（M4）", .computer, .landscape) == "Snug MacBook Air")
        #expect(name("华为 MatePad Pro 13.2 英寸", .tablet, .landscape) == "Snug 华为 MatePad Pro")
        #expect(name("通用 1920 × 1080", .computer, .landscape) == "Snug 电脑")
        #expect(name(nil, .tablet, .landscape) == "Snug 平板")
        #expect(name(nil, .phone, .portrait) == "Snug 手机")
    }
}
