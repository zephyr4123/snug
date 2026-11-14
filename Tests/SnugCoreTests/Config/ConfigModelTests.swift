import Foundation
import Testing
@testable import SnugCore

@Suite("配置 AppConfig")
struct ConfigModelTests {
    @Test("默认值：手机屏和手势都开着，字号默认放大 2 级，还没看过欢迎页，从腾讯云更新")
    func defaults() {
        let c = AppConfig()
        #expect(c.phoneScreen)
        #expect(c.gestures)
        #expect(c.zoomSteps == 2)
        #expect(!c.welcomed)
        #expect(c.updateSource == .tencent)
        #expect(c.lastVersion == nil)
    }

    @Test("不认识的更新源（比如更新的版本写的）用默认值，不把整份配置判为损坏")
    func unknownUpdateSource() throws {
        let c = try JSONDecoder().decode(AppConfig.self, from: Data(#"{"updateSource":"mirror","zoomSteps":3}"#.utf8))
        #expect(c.updateSource == .tencent)
        #expect(c.zoomSteps == 3)
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
        c.updateSource = .github
        c.lastVersion = Version(major: 2, minor: 1, patch: 0)
        #expect(try JSONDecoder().decode(AppConfig.self, from: JSONEncoder().encode(c)) == c)
    }
}
