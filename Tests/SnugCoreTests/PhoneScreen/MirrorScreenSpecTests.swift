import CoreGraphics
import Testing
@testable import SnugCore

@Suite("内建屏镜像的规格")
struct MirrorScreenSpecTests {
    @Test("2 倍内建屏：虚拟屏的像素是点尺寸的两倍")
    func retinaPixelSize() {
        let pixels = MirrorScreenSpec.pixelSize(pointSize: CGSize(width: 1512, height: 982), scale: 2)
        #expect(pixels == CGSize(width: 3024, height: 1964))
    }

    @Test("1 倍内建屏：按原尺寸建，不会算出 0")
    func nonRetinaPixelSize() {
        let pixels = MirrorScreenSpec.pixelSize(pointSize: CGSize(width: 1440, height: 900), scale: 1)
        #expect(pixels == CGSize(width: 1440, height: 900))
    }

    @Test("物理尺寸按像素上限、约 220ppi 折算")
    func millimeters() {
        let mm = MirrorScreenSpec.millimeters(pointSize: CGSize(width: 1512, height: 982), scale: 2)
        #expect(abs(mm.width - 349.2) < 0.5)
        #expect(abs(mm.height - 226.8) < 0.5)
    }

    @Test("身份和手机屏分开：系统不会把两块屏记成同一块")
    func identityIsSeparateFromPhoneScreen() {
        #expect(MirrorScreenSpec.serials.allSatisfy { !PhoneScreenSpec.serials.contains($0) })
        #expect(MirrorScreenSpec.productID != PhoneScreenSpec.productID)
    }
}
