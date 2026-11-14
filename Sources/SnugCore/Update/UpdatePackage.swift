// 更新包：一个版本的 Snug.app 怎么从块拼出来。
// 包（Snug-<版本>.pack）里依次放着这个版本用到的每一块：去重，逐块 LZMA 压缩，首尾相接。
// 清单记着每块在包里的位置、每个文件由哪几块组成。发布时 make 打包；更新时把装着的 Snug.app 切开（chunks(in:)），
// 本机没有的块按字节范围从包里取（missingRanges → unpack），拼出新版本（assemble）。
// 不挑从哪个版本升：缺什么取什么。每块都核对 sha256，拼出来的和发布的逐字节相同，签名照旧有效
import Foundation

public struct UpdatePackage: Codable, Equatable, Sendable {
    /// 包的文件名，和 update.json 放在同一个版本下
    public let file: String
    /// 切法（Chunker.algorithm）。只是记一笔：切法不同块照样按 sha256 认，只是认得出的少了
    public let chunking: String
    /// 包里的块，按在包里的顺序
    public let chunks: [Chunk]
    public let files: [File]

    public struct Chunk: Codable, Equatable, Sendable {
        public let sha256: String
        /// 原始字节数
        public let size: Int
        /// 在包里从哪个字节开始、占多少字节（压过的）
        public let offset: Int
        public let length: Int

        public init(sha256: String, size: Int, offset: Int, length: Int) {
            self.sha256 = sha256
            self.size = size
            self.offset = offset
            self.length = length
        }
    }

    public struct File: Codable, Equatable, Sendable {
        /// 相对应用包，比如 Contents/MacOS/Snug
        public let path: String
        public let executable: Bool
        /// 依次由哪几块拼成（chunks 的下标）。空文件没有块
        public let chunks: [Int]

        public init(path: String, executable: Bool, chunks: [Int]) {
            self.path = path
            self.executable = executable
            self.chunks = chunks
        }
    }

    public init(file: String, chunking: String, chunks: [Chunk], files: [File]) {
        self.file = file
        self.chunking = chunking
        self.chunks = chunks
        self.files = files
    }

    // MARK: 发布

    /// 把应用包切块打成包，交回清单和包的内容。同样的应用包每次打出来一字不差
    public static func make(app: URL, file: String) throws -> (package: UpdatePackage, pack: Data) {
        var pack = Data()
        var chunks: [Chunk] = []
        var known: [String: Int] = [:]
        let files = try tree(of: app).map { item in
            let ids = try Chunker.cuts(item.data).map { cut in
                let raw = item.data[cut]
                let sha = raw.sha256
                if let id = known[sha] { return id }
                let packed = try (Data(raw) as NSData).compressed(using: .lzma) as Data
                known[sha] = chunks.count
                chunks.append(Chunk(sha256: sha, size: raw.count, offset: pack.count, length: packed.count))
                pack.append(packed)
                return chunks.count - 1
            }
            return File(path: item.path, executable: item.executable, chunks: ids)
        }
        return (UpdatePackage(file: file, chunking: Chunker.algorithm, chunks: chunks, files: files), pack)
    }

    // MARK: 更新

    /// 本机已有的块：把装着的应用包按同样的切法切开，sha256 → 内容
    public static func chunks(in app: URL) throws -> [String: Data] {
        var chunks: [String: Data] = [:]
        for item in try tree(of: app) {
            for cut in Chunker.cuts(item.data) {
                let raw = item.data[cut]
                chunks[raw.sha256] = Data(raw)
            }
        }
        return chunks
    }

    /// 还缺的块在包里的字节范围：按包里的顺序，相邻的并成一段（一段一次请求）
    public func missingRanges(have: [String: Data]) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        for chunk in chunks where have[chunk.sha256] == nil {
            let range = chunk.offset ..< chunk.offset + chunk.length
            if let last = ranges.last, last.upperBound == range.lowerBound {
                ranges[ranges.count - 1] = last.lowerBound ..< range.upperBound
            } else {
                ranges.append(range)
            }
        }
        return ranges
    }

    /// 从包里取回的一段（range 是它在包里的位置）解出其中的块，逐块核对
    public func unpack(_ data: Data, at range: Range<Int>) throws -> [String: Data] {
        guard data.count == range.count else {
            throw UpdateError.corruptDownload("取回 \(data.count) 字节，应为 \(range.count)")
        }
        var out: [String: Data] = [:]
        for chunk in chunks where chunk.offset >= range.lowerBound && chunk.offset + chunk.length <= range.upperBound {
            let start = data.startIndex + chunk.offset - range.lowerBound
            let raw = try? (Data(data[start ..< start + chunk.length]) as NSData).decompressed(using: .lzma) as Data
            guard let raw, raw.count == chunk.size, raw.sha256 == chunk.sha256 else {
                throw UpdateError.corruptDownload("块 \(chunk.sha256.prefix(12)) 对不上")
            }
            out[chunk.sha256] = raw
        }
        return out
    }

    /// 用这些块拼出这个版本的应用包，放到 dest（还不存在的目录）。块要先取齐
    public func assemble(into dest: URL, from available: [String: Data]) throws {
        guard missingRanges(have: available).isEmpty else { throw UpdateError.missingChunk }
        let fm = FileManager.default
        for file in files {
            let url = dest.appendingPathComponent(file.path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = file.chunks.reduce(into: Data()) { data, id in data.append(available[chunks[id].sha256]!) }
            try data.write(to: url, options: .withoutOverwriting)
            try fm.setAttributes([.posixPermissions: file.executable ? 0o755 : 0o644], ofItemAtPath: url.path)
        }
    }

    // MARK: 核对

    /// update.json 解析后核对一遍（UpdateFeed.decode 调）：包是一个普通的文件名，块在包里首尾相接，
    /// 文件的路径都在应用包里面、块的下标都在
    func validate() throws {
        guard !file.isEmpty, !file.contains("/"), file != ".." else { throw UpdateError.malformed("包的文件名不对：\(file)") }
        var offset = 0
        for chunk in chunks {
            guard chunk.offset == offset, chunk.length > 0, chunk.size > 0 else {
                throw UpdateError.malformed("块 \(chunk.sha256.prefix(12)) 在包里的位置不对")
            }
            offset += chunk.length
        }
        for file in files {
            let parts = file.path.split(separator: "/", omittingEmptySubsequences: false)
            guard parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
                throw UpdateError.malformed("路径不对：\(file.path)")
            }
            guard file.chunks.allSatisfy(chunks.indices.contains) else {
                throw UpdateError.malformed("\(file.path) 用到的块不在清单里")
            }
        }
    }

    /// 应用包里的每个文件，按路径排好。目录不单独记（拼的时候按路径建）；符号链接之类的不收
    private static func tree(of root: URL) throws -> [(path: String, data: Data, executable: Bool)] {
        let fm = FileManager.default
        return try fm.subpathsOfDirectory(atPath: root.path).sorted().compactMap { path in
            let url = root.appendingPathComponent(path)
            let attributes = try fm.attributesOfItem(atPath: url.path)
            switch attributes[.type] as? FileAttributeType {
            case .typeDirectory?:
                return nil
            case .typeRegular?:
                let mode = attributes[.posixPermissions] as? Int ?? 0
                return (path, try Data(contentsOf: url), mode & 0o111 != 0)
            default:
                throw UpdateError.unsupportedItem(path)
            }
        }
    }
}
