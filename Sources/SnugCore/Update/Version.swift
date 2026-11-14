// 版本号：主.次.修订，按数比大小（2.10.0 比 2.9.9 新）。Snug 只发正式版，和 scripts/snug 认的写法一样
import Foundation

public struct Version: Comparable, Hashable, Sendable, Codable, LosslessStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public init?(_ description: String) {
        let parts = description.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { ("0"..."9").contains($0) } }) else { return nil }
        let numbers = parts.compactMap { Int($0) }
        guard parts.count == 3, numbers.count == 3 else { return nil }
        self.init(major: numbers[0], minor: numbers[1], patch: numbers[2])
    }

    public var description: String { "\(major).\(minor).\(patch)" }

    public static func < (a: Version, b: Version) -> Bool {
        (a.major, a.minor, a.patch) < (b.major, b.minor, b.patch)
    }

    public init(from decoder: any Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let version = Version(text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "不是版本号：\(text)"))
        }
        self = version
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
