import CoreGraphics
import Testing
@testable import SnugCore

private let ipad = DeviceChoice(model: "Apple iPad（第 10 代）", screen: DeviceScreen(width: 1640, height: 2360, points: 820), kind: .tablet)
/// 安卓平板不知道逻辑分辨率（按 800 点估）
private let xiaomiPad = DeviceChoice(model: "小米 Xiaomi Pad 7", screen: DeviceScreen(width: 2136, height: 3200), kind: .tablet)
/// 屏幕 1084 像素宽：最清晰（542）紧挨着默认档 540
private let nova = DeviceChoice(model: "华为 nova 13", screen: DeviceScreen(width: 1084, height: 2412))
/// 折叠屏内屏：横屏比方形还宽，ScreenFit 夹成方屏
private let findN5 = DeviceChoice(model: "OPPO Find N5 内屏", screen: DeviceScreen(width: 2248, height: 2480))
private let air = DeviceChoice(model: "Apple MacBook Air 13 英寸（M4）", screen: DeviceScreen(width: 956, height: 1470, notch: 33), kind: .computer)

@Suite("分辨率 ScreenResolution")
struct ScreenResolutionTests {
    @Test("iPhone 17 Pro Max 竖屏：540（默认）到 1080；660 时 2 倍像素正好是屏幕的 1320，默认只有 81%")
    func phonePortrait() throws {
        let r = try #require(ScreenResolution(device: .standard, orientation: .portrait))
        #expect(r.range == 540...1080)
        #expect(r.sharpest == 660)
        #expect(r.clarity(at: 540) == .soft(percent: 81))
        #expect(r.clarity(at: 660) == .sharpest)
        #expect(r.clarity(at: 800) == .beyond)
        #expect(r.size(width: 540) == CGSize(width: 540, height: 950))
    }

    @Test("iPhone 17 Pro Max 横屏：宽度方向扣掉远控左右让出的 154 点，屏幕像素 2406，最清晰在 1203")
    func phoneLandscape() throws {
        let r = try #require(ScreenResolution(device: .standard, orientation: .landscape))
        #expect(r.range == 957...1907)
        #expect(r.sharpest == 1203)
    }

    @Test("iPad（第 10 代）横屏：952（默认，逻辑宽度 ÷ 1.24）到 1902（默认往上每 10 点一档，不超过 2 倍）；最清晰在 1180，默认 80%")
    func tablet() throws {
        let r = try #require(ScreenResolution(device: ipad, orientation: .landscape))
        #expect(r.range == 952...1902)
        #expect(r.sharpest == 1180)
        #expect(r.clarity(at: 952) == .soft(percent: 80))
        #expect(r.clarity(at: 1180) == .sharpest)
        let portrait = try #require(ScreenResolution(device: ipad, orientation: .portrait))
        #expect(portrait.sharpest == 820)
    }

    @Test("安卓平板没有逻辑分辨率：按 800 点估默认档，最清晰照样按屏幕像素算")
    func androidTablet() throws {
        let r = try #require(ScreenResolution(device: xiaomiPad, orientation: .landscape))
        #expect(r.range == 967...1927)
        #expect(r.sharpest == 1600)
        #expect(r.clarity(at: 967) == .soft(percent: 60))
    }

    @Test("自己填的是比例（9 × 20）、或屏幕像素比默认档还少：不知道屏幕有多少像素，不报清晰度、没有最清晰那一格")
    func unknownPixels() throws {
        let ratio = DeviceChoice(model: nil, screen: DeviceScreen(width: 9, height: 20))
        let r = try #require(ScreenResolution(device: ratio, orientation: .portrait))
        #expect(r.sharpest == nil)
        #expect(r.clarity(at: r.range.lowerBound) == nil)
        #expect(r.clarity(at: r.range.upperBound) == nil)
    }

    @Test("屏幕像素正好够默认档（1080 × 2400）：默认就是最清晰，没有单独那一格")
    func defaultIsSharpest() throws {
        let r = try #require(ScreenResolution(device: DeviceChoice(model: nil, screen: DeviceScreen(width: 1080, height: 2400)), orientation: .portrait))
        #expect(r.sharpest == nil)
        #expect(r.clarity(at: 540) == .sharpest)
        #expect(r.clarity(at: 600) == .beyond)
    }

    @Test("差一点到最清晰时不报 100%：百分比向下取整")
    func percentFloors() throws {
        let r = try #require(ScreenResolution(device: .standard, orientation: .portrait))
        #expect(r.clarity(at: 659) == .soft(percent: 99))
    }

    @Test("电脑屏没有分辨率可调：照搬电脑自己的分辨率")
    func computer() {
        #expect(ScreenResolution(device: air, orientation: .landscape) == nil)
    }

    @Test("滑块取值：从默认起每 10 点一格；靠近最清晰时吸到那一格；两头够得着、出界夹回")
    func snapped() throws {
        let r = try #require(ScreenResolution(device: ipad, orientation: .landscape))
        #expect(r.snapped(952) == 952)
        #expect(r.snapped(958) == 962)
        #expect(r.snapped(1172) == 1180)
        #expect(r.snapped(1189) == 1180)
        #expect(r.snapped(1200) == 1202)
        #expect(r.snapped(1899) == 1902)
        #expect(r.snapped(2400) == 1902)
        #expect(r.snapped(100) == 952)
    }

    @Test("最清晰紧挨着两头时，两头照样够得着；拖到头就是头")
    func snappedEnds() throws {
        let phone = try #require(ScreenResolution(device: nova, orientation: .portrait))
        #expect(phone.range == 540...1080)
        #expect(phone.sharpest == 542)
        #expect(phone.snapped(540) == 540)
        #expect(phone.snapped(547) == 542)
        #expect(phone.snapped(542) == 542)
        let pad = try #require(ScreenResolution(device: xiaomiPad, orientation: .portrait))
        #expect(pad.range == 645...1075)
        #expect(pad.sharpest == 1068)
        #expect(pad.snapped(1075) == 1075)
        #expect(pad.snapped(1072) == 1068)
    }

    @Test("吸出来的每一档再吸一次不变：屏上开始滑动时先按现在的值吸一次，不能跳")
    func snappedIsStable() throws {
        for (device, orientation) in [(DeviceChoice.standard, Orientation.portrait), (nova, .portrait), (xiaomiPad, .portrait), (ipad, .landscape)] {
            let r = try #require(ScreenResolution(device: device, orientation: orientation))
            for value in stride(from: Double(r.range.lowerBound), through: Double(r.range.upperBound), by: 0.5) {
                let width = r.snapped(value)
                #expect(r.snapped(Double(width)) == width, "\(device.title) \(value) → \(width)")
            }
        }
    }

    @Test("加减一格（无障碍）：经过最清晰也挪得动，到头停住")
    func stepped() throws {
        let r = try #require(ScreenResolution(device: ipad, orientation: .landscape))
        #expect(r.stepped(1172, up: true) == 1180)
        #expect(r.stepped(1180, up: true) == 1192)
        #expect(r.stepped(1180, up: false) == 1162)
        #expect(r.stepped(1192, up: false) == 1180)
        #expect(r.stepped(952, up: false) == 952)
        #expect(r.stepped(1902, up: true) == 1902)
        let phone = try #require(ScreenResolution(device: nova, orientation: .portrait))
        #expect(phone.stepped(540, up: true) == 542)
        #expect(phone.stepped(542, up: false) == 540)
        #expect(phone.stepped(542, up: true) == 560)
    }

    @Test("折叠屏内屏横屏：ScreenFit 夹成方屏，远控铺满控制端屏幕的高，横向用到的是短边那 2248 像素")
    func foldableLandscape() throws {
        let r = try #require(ScreenResolution(device: findN5, orientation: .landscape))
        #expect(r.range == 800...1600)
        #expect(r.sharpest == 1124)
        #expect(r.clarity(at: 800) == .soft(percent: 71))
    }

    @Test("范围只有一档（逻辑宽度很大的平板竖屏，被像素上限卡住）：不崩，没有最清晰那一格")
    func singleTier() throws {
        let huge = DeviceChoice(model: nil, screen: DeviceScreen(width: 2680, height: 3600, points: 1340), kind: .tablet)
        let r = try #require(ScreenResolution(device: huge, orientation: .portrait))
        #expect(r.range == 1080...1080)
        #expect(r.sharpest == nil)
        #expect(r.snapped(1000) == 1080)
    }

    @Test("存进配置：默认存 nil；读出来的夹回范围（机型库改了数值、手改了配置）")
    func stored() throws {
        let r = try #require(ScreenResolution(device: ipad, orientation: .landscape))
        #expect(r.stored(952) == nil)
        #expect(r.stored(1180) == 1180)
        #expect(r.width(stored: nil) == 952)
        #expect(r.width(stored: 1180) == 1180)
        #expect(r.width(stored: 10) == 952)
        #expect(r.width(stored: 9999) == 1902)
    }

    @Test("范围和建屏用的 ScreenFit 一致：范围里每一档建出来就是那档，范围外夹回两头")
    func matchesScreenFit() throws {
        for (device, orientation) in [(DeviceChoice.standard, Orientation.portrait), (.standard, .landscape), (ipad, .portrait), (ipad, .landscape),
                                      (xiaomiPad, .landscape), (nova, .portrait), (findN5, .landscape)] {
            let r = try #require(ScreenResolution(device: device, orientation: orientation))
            let fit = { (width: Int) in ScreenFit(device: device.screen, kind: device.kind, orientation: orientation, width: width).baseWidth }
            for width in stride(from: r.range.lowerBound, through: r.range.upperBound, by: 37) {
                #expect(fit(width) == width)
            }
            #expect(fit(r.range.upperBound) == r.range.upperBound)
            #expect(fit(r.range.upperBound + 100) == r.range.upperBound)
            #expect(fit(r.range.lowerBound - 100) == r.range.lowerBound)
        }
    }
}
