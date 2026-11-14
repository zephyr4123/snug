// update.json：最新的发布。发布时由 snug-release 写（scripts/snug ship 传到 GitHub 和国内源），
// App 每次启动取一次：版本号决定有没有新版本，更新日志给用户看落下了什么，清单（UpdatePackage）照着拼新版本
import Foundation

public struct UpdateFeed: Codable, Equatable, Sendable {
    /// 格式号。改了装着的旧版本看不懂的东西（清单结构、下载地址的摆法）就加一：
    /// 旧版本看到更新的格式号会请用户去下载新版，而不是报错或一直以为自己是最新的
    public static let format = 1

    public let format: Int
    public let version: Version
    /// 各版本的更新日志，新的在前
    public let releases: [ReleaseNote]
    public let package: UpdatePackage

    public init(version: Version, releases: [ReleaseNote], package: UpdatePackage) {
        format = Self.format
        self.version = version
        self.releases = releases
        self.package = package
    }

    /// 解析并核对 update.json。核对过的清单路径都在应用包里面、块的位置和下标都对得上，后面拼的时候不用再防
    public static func decode(_ data: Data) throws -> UpdateFeed {
        struct Header: Decodable { let format: Int }
        func decode<T: Decodable>(_ type: T.Type) throws -> T {
            do { return try JSONDecoder().decode(type, from: data) } catch {
                throw UpdateError.malformed("update.json 解析不了：\(error)")
            }
        }
        let format = try decode(Header.self).format
        guard format == Self.format else {
            throw format > Self.format ? UpdateError.newerFormat : UpdateError.malformed("update.json 的格式号是 \(format)")
        }
        let feed = try decode(UpdateFeed.self)
        try feed.package.validate()
        return feed
    }

    /// 比 current 新的那几版的更新日志，新的在前
    public func releases(after current: Version) -> [ReleaseNote] {
        releases.filter { $0.version > current }
    }
}

/// 一个版本的更新日志，取自它的标签说明（git tag -a 写的那段，也是 GitHub Release 的说明）
public struct ReleaseNote: Codable, Equatable, Sendable {
    public let version: Version
    /// 发布日期，yyyy-MM-dd
    public let date: String
    public let title: String
    /// 正文：每行一个小标题、条目（「- 」开头）或段落，节与节之间空一行
    public let body: String

    public init(version: Version, date: String, title: String, body: String) {
        self.version = version
        self.date = date
        self.title = title
        self.body = body
    }

    /// 标签说明 → 更新日志。第一行去掉开头的「Snug 2.0.1：」当标题；
    /// 「安装」一节（下载 dmg、拖进「应用程序」）是写给 GitHub 上手动下载的人的，App 里更新用不着，去掉
    public init(version: Version, date: String, tagMessage: String) {
        var lines = tagMessage.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        let first = lines.isEmpty ? "" : lines.removeFirst()
        let prefix = "Snug \(version)："
        let title = first.hasPrefix(prefix) ? String(first.dropFirst(prefix.count)) : first
        var body: [String] = []
        var skipping = false
        for line in lines {
            if line == "安装" { skipping = true }
            if skipping {
                skipping = !line.isEmpty
                continue
            }
            if !(line.isEmpty && (body.last?.isEmpty ?? true)) { body.append(line) }
        }
        while body.last?.isEmpty == true { body.removeLast() }
        self.init(version: version, date: date, title: title, body: body.joined(separator: "\n"))
    }

    public enum Block: Equatable, Sendable {
        case heading(String)
        case bullet(String)
        case paragraph(String)
    }

    /// 正文分成小标题、条目、段落：下一行是条目的那行算小标题（「修复」「其他」这样的节名）
    public var blocks: [Block] {
        let lines = body.split(separator: "\n").map(String.init)
        return lines.indices.map { i in
            let line = lines[i]
            if line.hasPrefix("- ") { return .bullet(String(line.dropFirst(2))) }
            return i + 1 < lines.count && lines[i + 1].hasPrefix("- ") ? .heading(line) : .paragraph(line)
        }
    }
}

public enum UpdateError: Error, Equatable, Sendable, CustomStringConvertible {
    /// update.json 的格式号比这一版认得的新：这一版拼不出新版本，只能请用户去下载
    case newerFormat
    /// update.json 或清单不对
    case malformed(String)
    /// 取回来的内容不完整、解不开，或者和 sha256 对不上
    case corruptDownload(String)
    /// 拼的时候缺块（应当先按 missingRanges 取齐）
    case missingChunk
    /// 发布时：应用包里有包格式不收的东西
    case unsupportedItem(String)

    public var description: String {
        switch self {
        case .newerFormat: "update.json 的格式比这一版新"
        case .malformed(let why): why
        case .corruptDownload(let why): "下载的内容不对：\(why)"
        case .missingChunk: "拼新版本时缺块"
        case .unsupportedItem(let path): "\(path) 不是普通文件或目录，更新包不收"
        }
    }
}
