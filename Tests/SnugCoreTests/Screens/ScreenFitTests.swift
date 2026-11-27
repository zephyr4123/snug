import CoreGraphics
import Testing
@testable import SnugCore

private func phone(_ screen: DeviceScreen) -> ScreenFit { ScreenFit(device: screen, kind: .phone, orientation: .portrait) }

@Suite("屏幕适配 ScreenFit")
struct ScreenFitTests {
    /// 基准宽度下的可放区域：950 扣掉菜单栏 25、小横条 28
    private let baseArea = CGSize(width: 540, height: 897)
    private let fit = ScreenFit.standard

    @Test("没选过手机（iPhone 17 Pro Max）：还是原来的 540×950，档位 540 到 1080、每 10 点一档、比例都一样")
    func standard() {
        #expect(fit.size(width: 540) == CGSize(width: 540, height: 950))
        #expect(fit.size(width: 1080) == CGSize(width: 1080, height: 1900))
        #expect(fit.widths.first == 540)
        #expect(fit.widths.last == 1080)
        #expect(zip(fit.widths, fit.widths.dropFirst()).allSatisfy { $1 - $0 == 10 })
        for width in fit.widths {
            let size = fit.size(width: width)
            #expect(abs(size.height / size.width - 950.0 / 540) < 0.002)
        }
    }

    @Test("竖屏的像素上限框住所有比例：最宽一档 × 最长比例的 2 倍")
    func maxPixels() {
        #expect(ScreenFit.portraitPixels == CGSize(width: 2160, height: 4320))
        let longest = ScreenFit(ratio: 2)
        #expect(longest.size(width: 1080).height * 2 == ScreenFit.portraitPixels.height)
    }

    // 91 点按 UU远程 的工具栏实测（ScreenFit.clientToolbarInset）
    @Test("比例 = 手机屏幕的高宽比扣掉上下各 91 点（远控工具栏）；不知道逻辑宽度按 400 点估")
    func ratio() {
        // 20:9 安卓 1080×2400：2.222 - 182/400 = 1.767
        let android = phone(DeviceScreen(width: 1080, height: 2400))
        #expect(abs(android.ratio - (2400.0 / 1080 - 182.0 / 400)) < 1e-9)
        #expect(android.baseWidth == 540)
        #expect(android.size(width: 540) == CGSize(width: 540, height: 954))
        // 只看比例：自己填 9×20 和 1080×2400 一样
        #expect(phone(DeviceScreen(width: 9, height: 20)) == android)
    }

    @Test("矮的屏（16:9 的 iPhone 8）：540 宽时高不到 800、没有 2 倍，基准加宽到够高的一档")
    func shortScreen() {
        let iPhone8 = phone(DeviceScreen(width: 750, height: 1334, points: 375))
        #expect(iPhone8.baseWidth == 620)
        #expect(iPhone8.size(width: 620).height >= 800)
        #expect(iPhone8.size(width: 610).height < 800)
        #expect(iPhone8.widths.first == 620)
        #expect(iPhone8.widths.last == 1080)
    }

    @Test("比例夹在 1 到 2：折叠屏内屏扣完比正方形还方按正方形（基准 800×800）；太长的按 2")
    func clamped() {
        let fold = phone(DeviceScreen(width: 1856, height: 2160))
        #expect(fold.ratio == 1)
        #expect(fold.size(width: fold.baseWidth) == CGSize(width: 800, height: 800))
        let tall = phone(DeviceScreen(width: 9, height: 30))
        #expect(tall.ratio == 2)
        #expect(tall.size(width: 540) == CGSize(width: 540, height: 1080))
    }

    @Test("竖屏手机任何比例的每一档都宽 ≥ 540、高 ≥ 800，也都在像素上限里")
    func everyStepIsHiDPI() {
        for r in stride(from: 0.8, through: 2.4, by: 0.01) {
            let f = ScreenFit(ratio: r)
            #expect(!f.widths.isEmpty)
            for width in f.widths {
                let size = f.size(width: width)
                #expect(size.width >= CGFloat(ScreenFit.minPhoneWidth) && size.height >= CGFloat(ScreenFit.minLongSide))
                #expect(size.width * 2 <= ScreenFit.portraitPixels.width && size.height * 2 <= ScreenFit.portraitPixels.height)
            }
        }
    }

    @Test("别的屏任何比例、任何想要的宽度：每一档都过 2 倍门槛（长边 ≥ 800、短边 ≥ 525），都在这个方向的像素上限里，最宽到基准的 2 倍",
          arguments: Orientation.allCases)
    func everyStepIsHiDPIElsewhere(orientation: Orientation) {
        let ratios = orientation == .portrait ? stride(from: 0.9, through: 2.1, by: 0.01) : stride(from: 0.25, through: 1.05, by: 0.01)
        let pixels = orientation == .portrait ? ScreenFit.portraitPixels : ScreenFit.landscapePixels
        for r in ratios {
            for wanted in [nil, 300, 661, 952, 1470, 2560, 5000] as [Int?] {
                let f = ScreenFit(ratio: r, orientation: orientation, width: wanted)
                #expect(!f.widths.isEmpty)
                #expect(f.widths.last! <= f.baseWidth * 2)
                for width in f.widths {
                    let size = f.size(width: width)
                    #expect(max(size.width, size.height) >= 800 && min(size.width, size.height) >= 525, "\(r) \(width)")
                    #expect((size.width >= size.height) == (orientation == .landscape) || f.ratio == 1)
                    #expect(size.width * 2 <= pixels.width && size.height * 2 <= pixels.height, "\(r) \(width)")
                }
            }
        }
    }

    // 左右 82+72 点按 UU远程 的工具栏和暗带实测（ScreenFit.clientLandscapeInsets）
    @Test("手机横屏：扣掉左右远控的工具栏和暗带（154 个手机点），取 2 倍门槛里最窄的一档，短边 525")
    func phoneLandscape() {
        let f = ScreenFit(device: DeviceChoice.standard.screen, kind: .phone, orientation: .landscape)
        // 17 Pro Max 横放 956×440 点，扣完 802×440
        #expect(abs(f.ratio - 440.0 / 802) < 1e-9)
        #expect(f.size(width: f.baseWidth) == CGSize(width: 957, height: 525))
        #expect(f.size(width: f.baseWidth - 1).height < 525)
        #expect(f.widths.last == 1907)
    }

    @Test("登记给系统时最宽的在前：第一档比像素上限小太多屏不上线（实测 6144×3840 上限下 2 倍高 1050 像素的不上线；机型库每一条见 bundledFits）")
    func registrationOrder() {
        let landscape = ScreenFit(device: DeviceChoice.standard.screen, kind: .phone, orientation: .landscape)
        #expect(landscape.registrationOrder.first == landscape.widths.last)
        #expect(landscape.registrationOrder == landscape.widths.reversed())
    }

    @Test("平板不扣，横竖都铺满；基准是逻辑分辨率除以 1.24（V10：iPad 第 10 代竖 660×950、横 950×660 上下）")
    func tablet() {
        let ipad = DeviceScreen(width: 1640, height: 2360, points: 820)
        let portrait = ScreenFit(device: ipad, kind: .tablet, orientation: .portrait)
        #expect(portrait.size(width: portrait.baseWidth) == CGSize(width: 661, height: 951))
        let landscape = ScreenFit(device: ipad, kind: .tablet, orientation: .landscape)
        #expect(landscape.size(width: landscape.baseWidth) == CGSize(width: 952, height: 662))
        // 安卓平板不知道逻辑分辨率：短边按 800 点估
        let android = ScreenFit(device: DeviceScreen(width: 2136, height: 3200), kind: .tablet, orientation: .landscape)
        #expect(android.baseWidth == 967)
    }

    @Test("电脑照搬自己的分辨率；有刘海的扣掉顶上那一条（Air 13：1470×956 → 1470×923，一像素对一像素）")
    func computer() {
        let air = ScreenFit(device: DeviceScreen(width: 956, height: 1470, notch: 33), kind: .computer, orientation: .landscape)
        #expect(air.size(width: air.baseWidth) == CGSize(width: 1470, height: 923))
        #expect(air.widths.last == 2940)
        let monitor = ScreenFit(device: DeviceScreen(width: 1080, height: 1920), kind: .computer, orientation: .landscape)
        #expect(monitor.size(width: monitor.baseWidth) == CGSize(width: 1920, height: 1080))
        // 超出像素上限（3072 宽）的按上限，字大一点
        let wide = ScreenFit(device: DeviceScreen(width: 2160, height: 3840), kind: .computer, orientation: .landscape)
        #expect(wide.baseWidth == 3072)
        // 竖着用的显示器
        let tall = ScreenFit(device: DeviceScreen(width: 1080, height: 1920), kind: .computer, orientation: .portrait)
        #expect(tall.size(width: tall.baseWidth) == CGSize(width: 1080, height: 1920))
    }

    @Test("装得下就不换（App 取整差一两点也算装得下）")
    func fits() {
        #expect(fit.width(toFit: baseArea, in: baseArea, at: 540) == 540)
        #expect(fit.width(toFit: CGSize(width: 400, height: 600), in: baseArea, at: 540) == 540)
        #expect(fit.width(toFit: CGSize(width: 542, height: 898), in: baseArea, at: 540) == 540)
    }

    @Test("宽度超了：装得下的最窄一档（系统设置 740、Safari 574、Typeless 988）")
    func wider() {
        #expect(fit.width(toFit: CGSize(width: 740, height: 897), in: baseArea, at: 540) == 740)
        #expect(fit.width(toFit: CGSize(width: 574, height: 897), in: baseArea, at: 540) == 580)
        #expect(fit.width(toFit: CGSize(width: 988, height: 897), in: baseArea, at: 540) == 990)
        // 正好是整档的最小宽度：浮点误差不能让它多进一档
        #expect(fit.width(toFit: CGSize(width: 580, height: 897), in: baseArea, at: 540) == 580)
        #expect(fit.width(toFit: CGSize(width: 850, height: 897), in: baseArea, at: 540) == 850)
    }

    @Test("高度超了：按高度等比换档，宽高比不变（不会又高又窄）")
    func taller() {
        // 540 × 1000 / 897 ≈ 602 → 610；610 那一档可放区域高 1073 - 25 - 32 = 1016，装得下 1000
        #expect(fit.width(toFit: CGSize(width: 540, height: 1000), in: baseArea, at: 540) == 610)
        // 宽高都超：按超得多的那一边
        #expect(fit.width(toFit: CGSize(width: 600, height: 1200), in: baseArea, at: 540) == 730)
    }

    @Test("比最宽一档还宽：用最宽一档")
    func capped() {
        #expect(fit.width(toFit: CGSize(width: 1200, height: 897), in: baseArea, at: 540) == 1080)
        #expect(fit.width(toFit: CGSize(width: 1200, height: 1838), in: CGSize(width: 1080, height: 1838), at: 1080) == 1080)
    }

    @Test("已经在更宽的一档时窗口又变宽了：按这一档的比例往上找")
    func fromWiderStep() {
        #expect(fit.width(toFit: CGSize(width: 800, height: 1242), in: CGSize(width: 740, height: 1242), at: 740) == 800)
    }

    @Test("Snug 自己的面板跟着档位放大，按短边算：小横条在手机上一样高，横竖拿着一样大")
    func scale() {
        #expect(ScreenFit.scale(screen: CGSize(width: 540, height: 950)) == 1)
        #expect(ScreenFit.scale(screen: CGSize(width: 1080, height: 1900)) == 2)
        #expect(ScreenFit.scale(screen: CGSize(width: 957, height: 525)) == 525.0 / 540)
        #expect(ScreenFit.homeBarHeight(screen: CGSize(width: 540, height: 950)) == 28)
        #expect(ScreenFit.homeBarHeight(screen: CGSize(width: 1080, height: 1900)) == 56)
        // V10 的 iPad：660 宽时 1.22 倍
        #expect(abs(ScreenFit.scale(screen: CGSize(width: 952, height: 662)) - 1.226) < 0.001)
    }

    @Test("分辨率选了更宽的基准：从它往上登记到它的 2 倍（手机竖屏到 1080 为止），比例不变")
    func chosenWidth() {
        let phone = ScreenFit(device: DeviceChoice.standard.screen, kind: .phone, orientation: .portrait, width: 660)
        #expect(phone.baseWidth == 660)
        #expect(phone.widths.first == 660)
        #expect(phone.widths.last == 1080)
        #expect(phone.ratio == ScreenFit.standard.ratio)
        let ipad = DeviceScreen(width: 1640, height: 2360, points: 820)
        let tablet = ScreenFit(device: ipad, kind: .tablet, orientation: .landscape, width: 1180)
        #expect(tablet.baseWidth == 1180)
        #expect(tablet.widths.last == 2360)
        #expect(tablet.ratio == ScreenFit(device: ipad, kind: .tablet, orientation: .landscape).ratio)
    }

    @Test("选的基准出了范围夹回去：不比默认窄，不比默认的最宽一档宽；电脑屏不认")
    func chosenWidthClamped() {
        let screen = DeviceChoice.standard.screen
        #expect(ScreenFit(device: screen, kind: .phone, orientation: .portrait, width: 300).baseWidth == 540)
        #expect(ScreenFit(device: screen, kind: .phone, orientation: .portrait, width: 5000).baseWidth == 1080)
        let ipad = DeviceScreen(width: 1640, height: 2360, points: 820)
        #expect(ScreenFit(device: ipad, kind: .tablet, orientation: .landscape, width: 5000).baseWidth == 1902)
        let air = DeviceScreen(width: 956, height: 1470, notch: 33)
        #expect(ScreenFit(device: air, kind: .computer, orientation: .landscape, width: 2000) == ScreenFit(device: air, kind: .computer, orientation: .landscape))
    }

    @Test("手势翻译的范围：整块屏，阈值按这一档放大")
    func touchRegion() {
        let screen = CGRect(x: 1512, y: 0, width: 1080, height: 1900)
        #expect(TouchRegion(screen: screen) == TouchRegion(frame: screen, scale: 2))
    }
}
