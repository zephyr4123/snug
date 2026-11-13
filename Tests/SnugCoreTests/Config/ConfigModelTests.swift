import Foundation
import Testing
@testable import SnugCore

@Suite("设备与配置模型")
struct ConfigModelTests {
    @Test("分辨率合法范围是 320...16384，宽高都要在范围内才算填好")
    func sizeValidation() {
        #expect(DeviceProfile.validSize == 320...16384)
        func profile(_ w: Int, _ h: Int) -> DeviceProfile {
            DeviceProfile(name: "iPhone", kind: .phone, width: w, height: h)
        }
        #expect(profile(320, 16384).hasSize)
        #expect(!profile(319, 1000).hasSize)
        #expect(!profile(1000, 16385).hasSize)
        #expect(!profile(0, 0).hasSize)
    }

    @Test("尺寸标签：高清带「高清」后缀")
    func sizeLabel() {
        #expect(DeviceProfile(name: "iPhone", kind: .phone, width: 2868, height: 1320).sizeLabel == "2868×1320 高清")
        #expect(DeviceProfile(name: "M1", kind: .computer, width: 1920, height: 1080, hiDPI: false).sizeLabel == "1920×1080")
    }

    @Test("AppConfig 默认值：虚拟屏是可选功能，默认关闭；其余开关也都默认关闭")
    func defaults() {
        let c = AppConfig()
        #expect(c.devices.isEmpty)
        #expect(c.paused == false)
        #expect(c.virtualDisplayEnabled == false)
        #expect(c.keepOnlyVirtual == false)
        #expect(c.watchdogEnabled == false)
        #expect(c.tourShown == false)
    }

    @Test("缺字段的 config.json 用默认值补齐，而不是整份判为损坏")
    func decodeMissingKeys() throws {
        let json = #"{"devices":[{"name":"iPad","kind":"tablet","width":2360,"height":1640}],"keepOnlyVirtual":true}"#
        let c = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        #expect(c.devices.count == 1)
        #expect(c.devices[0].hiDPI == true)
        #expect(c.keepOnlyVirtual == true)
        #expect(c.virtualDisplayEnabled == false)
        #expect(c.paused == false)
    }

    @Test("编码再解码保持不变；按名字查设备")
    func roundTripAndLookup() throws {
        var c = AppConfig()
        c.devices = [DeviceProfile(name: "iPhone", kind: .phone, width: 2868, height: 1320, uuComputer: false, platform: "ios")]
        c.virtualDisplayEnabled = true
        let back = try JSONDecoder().decode(AppConfig.self, from: JSONEncoder().encode(c))
        #expect(back == c)
        #expect(back.device(named: "iPhone")?.platform == "ios")
        #expect(back.device(named: "iPad") == nil)
        #expect(back.device(named: nil) == nil)
    }

    @Test("同显示规格：只比宽、高、高清，不比名字")
    func sameDisplaySpec() {
        let a = DeviceProfile(name: "A", kind: .phone, width: 2400, height: 1320)
        let b = DeviceProfile(name: "B", kind: .tablet, width: 2400, height: 1320)
        let c = DeviceProfile(name: "A", kind: .phone, width: 2400, height: 1320, hiDPI: false)
        #expect(a.hasSameDisplaySpec(as: b))
        #expect(!a.hasSameDisplaySpec(as: c))
    }
}
