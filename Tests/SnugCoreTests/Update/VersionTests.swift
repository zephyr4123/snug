import Foundation
import Testing
@testable import SnugCore

@Suite("版本号 Version")
struct VersionTests {
    @Test("只认主.次.修订三段数字", arguments: ["", "2.0", "2.0.1.4", "v2.0.1", "2.0.x", "2.0.-1", " 2.0.1", "2..1", "开发版"])
    func rejects(text: String) {
        #expect(Version(text) == nil)
    }

    @Test("解析与写回")
    func parses() {
        #expect(Version("2.0.1") == Version(major: 2, minor: 0, patch: 1))
        #expect(Version("10.20.30")?.description == "10.20.30")
    }

    @Test("按数比大小：2.10.0 比 2.9.9 新")
    func order() throws {
        let v = { (text: String) throws -> Version in try #require(Version(text)) }
        #expect(try v("2.10.0") > v("2.9.9"))
        #expect(try v("2.0.1") < v("2.1.0"))
        #expect(try v("3.0.0") > v("2.99.99"))
        #expect(try v("2.1.0") == v("2.1.0"))
    }

    @Test("JSON 里是字符串；不像版本号的解不开")
    func codable() throws {
        let data = try JSONEncoder().encode([Version(major: 2, minor: 1, patch: 0)])
        #expect(String(decoding: data, as: UTF8.self) == #"["2.1.0"]"#)
        #expect(try JSONDecoder().decode([Version].self, from: data) == [Version(major: 2, minor: 1, patch: 0)])
        #expect(throws: DecodingError.self) { try JSONDecoder().decode([Version].self, from: Data(#"["2.1"]"#.utf8)) }
    }
}
