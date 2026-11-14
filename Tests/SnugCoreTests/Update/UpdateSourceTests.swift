import Foundation
import Testing
@testable import SnugCore

@Suite("更新源 UpdateSource")
struct UpdateSourceTests {
    private let version = Version(major: 2, minor: 1, patch: 0)

    @Test("腾讯云：latest/update.json 和 v<版本>/ 下的包，与 scripts/snug 传的位置一致")
    func tencent() {
        let source = UpdateSource.tencent
        #expect(source.feedURL.absoluteString == "https://dl.zephyrxiang.com/snug/latest/update.json")
        #expect(source.url(of: "Snug-2.1.0.pack", in: version).absoluteString
            == "https://dl.zephyrxiang.com/snug/v2.1.0/Snug-2.1.0.pack")
        #expect(source.downloadPage.absoluteString == "https://dl.zephyrxiang.com/snug/latest/Snug.dmg")
    }

    @Test("GitHub：最新 Release 的 update.json，各版本 Release 下的包")
    func github() {
        let source = UpdateSource.github
        #expect(source.feedURL.absoluteString == "https://github.com/zephyr4123/snug/releases/latest/download/update.json")
        #expect(source.url(of: "Snug-2.1.0.pack", in: version).absoluteString
            == "https://github.com/zephyr4123/snug/releases/download/v2.1.0/Snug-2.1.0.pack")
        #expect(source.downloadPage.absoluteString == "https://github.com/zephyr4123/snug/releases/latest")
    }
}
