// 更新源：从哪取 update.json 和包。两处放的东西一样（scripts/snug ship 同时发），用户在「关于 Snug」里选
import Foundation

public enum UpdateSource: String, Codable, CaseIterable, Sendable {
    /// 国内源：腾讯云 COS + CDN，国内下载快
    case tencent
    /// GitHub Release
    case github

    public var title: String {
        switch self {
        case .tencent: "腾讯云"
        case .github: "GitHub"
        }
    }

    private static let tencentBase = URL(string: "https://dl.zephyrxiang.com/snug")!
    private static let githubBase = URL(string: "https://github.com/zephyr4123/snug/releases")!

    /// 最新发布的 update.json
    public var feedURL: URL {
        switch self {
        case .tencent: Self.tencentBase.appendingPathComponent("latest/update.json")
        case .github: Self.githubBase.appendingPathComponent("latest/download/update.json")
        }
    }

    /// 某个版本下的文件
    public func url(of file: String, in version: Version) -> URL {
        switch self {
        case .tencent: Self.tencentBase.appendingPathComponent("v\(version)").appendingPathComponent(file)
        case .github: Self.githubBase.appendingPathComponent("download/v\(version)").appendingPathComponent(file)
        }
    }

    /// 自己换不了时，请用户手动下载的地方
    public var downloadPage: URL {
        switch self {
        case .tencent: Self.tencentBase.appendingPathComponent("latest/Snug.dmg")
        case .github: Self.githubBase.appendingPathComponent("latest")
        }
    }
}
