import Foundation
import Testing
@testable import SnugCore

@Suite("配置 AppConfig")
struct ConfigModelTests {
    @Test("默认值：手机屏和手势都开着，字号默认放大 2 级，还没看过欢迎页")
    func defaults() {
        let c = AppConfig()
        #expect(c.phoneScreen)
        #expect(c.gestures)
        #expect(c.zoomSteps == 2)
        #expect(!c.welcomed)
    }

    @Test("缺字段的 config.json 用默认值补齐；旧版留下的字段忽略，而不是整份判为损坏")
    func decodeMissingAndLegacyKeys() throws {
        let json = #"{"gestures":false,"devices":[{"name":"iPad"}],"keepOnlyVirtual":true}"#
        let c = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        #expect(c.gestures == false)
        #expect(c.phoneScreen)
        #expect(c.zoomSteps == 2)
    }

    @Test("手改出界的字号级数夹回 0...4")
    func clampsZoomSteps() throws {
        let high = try JSONDecoder().decode(AppConfig.self, from: Data(#"{"zoomSteps":9}"#.utf8))
        let low = try JSONDecoder().decode(AppConfig.self, from: Data(#"{"zoomSteps":-3}"#.utf8))
        #expect(high.zoomSteps == 4)
        #expect(low.zoomSteps == 0)
    }

    @Test("编码再解码保持不变")
    func roundTrip() throws {
        var c = AppConfig()
        c.phoneScreen = false
        c.zoomSteps = 3
        c.welcomed = true
        #expect(try JSONDecoder().decode(AppConfig.self, from: JSONEncoder().encode(c)) == c)
    }
}
