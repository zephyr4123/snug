import CoreGraphics
import Testing
@testable import SnugCore

@Suite("屏幕适配 ScreenFit")
struct ScreenFitTests {
    /// 基准宽度下的可放区域：950 扣掉菜单栏 25、小横条 28
    private let baseArea = CGSize(width: 540, height: 897)

    @Test("档位：540 到 1080，每 10 点一档，宽高比都和 540×950 一样；像素上限是最宽一档的 2 倍")
    func ladder() {
        #expect(ScreenFit.widths.first == 540)
        #expect(ScreenFit.widths.last == 1080)
        #expect(zip(ScreenFit.widths, ScreenFit.widths.dropFirst()).allSatisfy { $1 - $0 == 10 })
        #expect(ScreenFit.size(width: 540) == CGSize(width: 540, height: 950))
        #expect(ScreenFit.size(width: 1080) == CGSize(width: 1080, height: 1900))
        for width in ScreenFit.widths {
            let size = ScreenFit.size(width: width)
            #expect(abs(size.height / size.width - 950.0 / 540) < 0.001)
        }
        #expect(ScreenFit.maxPixels == CGSize(width: 2160, height: 3800))
    }

    @Test("装得下就不换（App 取整差一两点也算装得下）")
    func fits() {
        #expect(ScreenFit.width(toFit: baseArea, in: baseArea, at: 540) == 540)
        #expect(ScreenFit.width(toFit: CGSize(width: 400, height: 600), in: baseArea, at: 540) == 540)
        #expect(ScreenFit.width(toFit: CGSize(width: 542, height: 898), in: baseArea, at: 540) == 540)
    }

    @Test("宽度超了：装得下的最窄一档（系统设置 740、Safari 574、Typeless 988）")
    func wider() {
        #expect(ScreenFit.width(toFit: CGSize(width: 740, height: 897), in: baseArea, at: 540) == 740)
        #expect(ScreenFit.width(toFit: CGSize(width: 574, height: 897), in: baseArea, at: 540) == 580)
        #expect(ScreenFit.width(toFit: CGSize(width: 988, height: 897), in: baseArea, at: 540) == 990)
    }

    @Test("高度超了：按高度等比换档，宽高比不变（不会又高又窄）")
    func taller() {
        // 540 × 1000 / 897 ≈ 602 → 610；610 那一档可放区域高 1073 - 25 - 32 = 1016，装得下 1000
        #expect(ScreenFit.width(toFit: CGSize(width: 540, height: 1000), in: baseArea, at: 540) == 610)
        // 宽高都超：按超得多的那一边
        #expect(ScreenFit.width(toFit: CGSize(width: 600, height: 1200), in: baseArea, at: 540) == 730)
    }

    @Test("比最宽一档还宽：用最宽一档")
    func capped() {
        #expect(ScreenFit.width(toFit: CGSize(width: 1200, height: 897), in: baseArea, at: 540) == 1080)
        #expect(ScreenFit.width(toFit: CGSize(width: 1200, height: 1838), in: CGSize(width: 1080, height: 1838), at: 1080) == 1080)
    }

    @Test("已经在更宽的一档时窗口又变宽了：按这一档的比例往上找")
    func fromWiderStep() {
        #expect(ScreenFit.width(toFit: CGSize(width: 800, height: 1242), in: CGSize(width: 740, height: 1242), at: 740) == 800)
    }

    @Test("Snug 自己的面板跟着档位放大：小横条在手机上一样高")
    func scale() {
        #expect(ScreenFit.scale(screenWidth: 540) == 1)
        #expect(ScreenFit.scale(screenWidth: 1080) == 2)
        #expect(ScreenFit.homeBarHeight(screenWidth: 540) == 28)
        #expect(ScreenFit.homeBarHeight(screenWidth: 1080) == 56)
    }
}
