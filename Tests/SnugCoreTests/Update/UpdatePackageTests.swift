import Foundation
import Testing
@testable import SnugCore

/// 照 Snug.app 的样子在临时目录里摆一个假的应用包：一个大的可执行文件、几个小文件、一个空文件
private func makeApp(at root: URL, binary: Data, plist: String) throws {
    let fm = FileManager.default
    let files: [(String, Data, Bool)] = [
        ("Contents/MacOS/Snug", binary, true),
        ("Contents/Info.plist", Data(plist.utf8), false),
        ("Contents/Resources/AppIcon.icns", randomBytes(90_000, seed: 7), false),
        ("Contents/Resources/Flow.bundle/Contents/Resources/en.lproj/Localizable.strings", Data("\"a\" = \"b\";".utf8), false),
        ("Contents/Resources/empty", Data(), false),
    ]
    for (path, data, executable) in files {
        let url = root.appendingPathComponent(path)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        try fm.setAttributes([.posixPermissions: executable ? 0o755 : 0o644], ofItemAtPath: url.path)
    }
}

/// 两棵树逐个文件比：路径、内容、可执行位都一样
private func expectSameTree(_ a: URL, _ b: URL, sourceLocation: SourceLocation = #_sourceLocation) throws {
    func snapshot(_ root: URL) throws -> [String: (Data, Bool)] {
        let fm = FileManager.default
        var out: [String: (Data, Bool)] = [:]
        for path in try fm.subpathsOfDirectory(atPath: root.path) {
            let url = root.appendingPathComponent(path)
            let attributes = try fm.attributesOfItem(atPath: url.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular else { continue }
            out[path] = (try Data(contentsOf: url), (attributes[.posixPermissions] as! Int) & 0o111 != 0)
        }
        return out
    }
    let (left, right) = (try snapshot(a), try snapshot(b))
    #expect(left.keys.sorted() == right.keys.sorted(), sourceLocation: sourceLocation)
    for (path, (data, executable)) in left {
        #expect(right[path]?.0 == data, "\(path) 内容不同", sourceLocation: sourceLocation)
        #expect(right[path]?.1 == executable, "\(path) 可执行位不同", sourceLocation: sourceLocation)
    }
}

@Suite("更新包 UpdatePackage")
struct UpdatePackageTests {
    let binary = randomBytes(1_500_000, seed: 11)

    @Test("打包再整包解开，拼出的应用包和原来逐字节一样（含可执行位、空文件）")
    func roundTrip() throws {
        let dir = try TempDir()
        let app = dir.url.appendingPathComponent("Snug.app"), out = dir.url.appendingPathComponent("out.app")
        try makeApp(at: app, binary: binary, plist: "<plist>2.1.0</plist>")
        let (package, pack) = try UpdatePackage.make(app: app, file: "Snug-2.1.0.pack")
        #expect(package.file == "Snug-2.1.0.pack")
        #expect(package.chunking == Chunker.algorithm)
        #expect(package.missingRanges(have: [:]) == [0..<pack.count])
        try package.assemble(into: out, from: package.unpack(pack, at: 0..<pack.count))
        try expectSameTree(app, out)
    }

    @Test("同样的内容只进包一次")
    func dedups() throws {
        let dir = try TempDir()
        let app = dir.url.appendingPathComponent("Snug.app")
        try makeApp(at: app, binary: binary, plist: "p")
        try binary.write(to: app.appendingPathComponent("Contents/MacOS/Copy"))
        let (package, _) = try UpdatePackage.make(app: app, file: "x.pack")
        #expect(Set(package.chunks.map(\.sha256)).count == package.chunks.count)
        let snug = try #require(package.files.first { $0.path == "Contents/MacOS/Snug" })
        let copy = try #require(package.files.first { $0.path == "Contents/MacOS/Copy" })
        #expect(snug.chunks == copy.chunks)
    }

    @Test("从旧版本升级：本机已有的块不下载，缺的相邻几块并成一段取，拼出的就是新版本")
    func updateFromOld() throws {
        let dir = try TempDir()
        let old = dir.url.appendingPathComponent("old.app"), new = dir.url.appendingPathComponent("new.app")
        let out = dir.url.appendingPathComponent("out.app")
        try makeApp(at: old, binary: binary, plist: "<plist>2.1.0</plist>")
        var changed = binary
        changed.insert(contentsOf: randomBytes(3000, seed: 12), at: 700_000)
        try makeApp(at: new, binary: changed, plist: "<plist>2.2.0</plist>")

        let (package, pack) = try UpdatePackage.make(app: new, file: "Snug-2.2.0.pack")
        var chunks = try UpdatePackage.chunks(in: old)
        let ranges = package.missingRanges(have: chunks)
        #expect(!ranges.isEmpty)
        #expect(ranges.map(\.count).reduce(0, +) < pack.count / 2)
        for (a, b) in zip(ranges, ranges.dropFirst()) { #expect(a.upperBound < b.lowerBound) }
        for range in ranges { chunks.merge(try package.unpack(pack[range], at: range)) { $1 } }
        try package.assemble(into: out, from: chunks)
        try expectSameTree(new, out)
        #expect(package.missingRanges(have: chunks) == [])
    }

    @Test("取回的内容坏了、短了，或者缺块，都不拼")
    func rejectsBadChunks() throws {
        let dir = try TempDir()
        let app = dir.url.appendingPathComponent("Snug.app")
        try makeApp(at: app, binary: binary, plist: "p")
        let (package, pack) = try UpdatePackage.make(app: app, file: "x.pack")
        var broken = pack
        broken[broken.count / 2] ^= 0xFF
        #expect(throws: UpdateError.self) { try package.unpack(broken, at: 0..<broken.count) }
        #expect(throws: UpdateError.self) { try package.unpack(pack.dropLast(), at: 0..<pack.count) }
        #expect(throws: UpdateError.missingChunk) {
            try package.assemble(into: dir.url.appendingPathComponent("out.app"), from: [:])
        }
    }

    @Test("包里不收符号链接：拼的时候不做，发布时就拦下")
    func rejectsSymlinks() throws {
        let dir = try TempDir()
        let app = dir.url.appendingPathComponent("Snug.app")
        try makeApp(at: app, binary: binary, plist: "p")
        try FileManager.default.createSymbolicLink(atPath: app.appendingPathComponent("Contents/link").path,
                                                   withDestinationPath: "MacOS/Snug")
        #expect(throws: UpdateError.self) { try UpdatePackage.make(app: app, file: "x.pack") }
    }
}

@Suite("update.json UpdateFeed")
struct UpdateFeedTests {
    private func feed(files: [UpdatePackage.File], chunks: [UpdatePackage.Chunk] = [], format: Int = UpdateFeed.format) -> Data {
        let package = UpdatePackage(file: "Snug-2.2.0.pack", chunking: Chunker.algorithm, chunks: chunks, files: files)
        var json = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(
            UpdateFeed(version: Version(major: 2, minor: 2, patch: 0), releases: [], package: package))) as! [String: Any]
        json["format"] = format
        return try! JSONSerialization.data(withJSONObject: json)
    }

    private let chunk = UpdatePackage.Chunk(sha256: String(repeating: "a", count: 64), size: 3, offset: 0, length: 3)

    @Test("读得懂这一版的格式")
    func decodes() throws {
        let decoded = try UpdateFeed.decode(feed(files: [.init(path: "Contents/Info.plist", executable: false, chunks: [0])],
                                                 chunks: [chunk]))
        #expect(decoded.version == Version(major: 2, minor: 2, patch: 0))
        #expect(decoded.package.files.map(\.path) == ["Contents/Info.plist"])
    }

    @Test("格式号比这一版新：说清楚是格式新了，不当成坏了")
    func newerFormat() {
        #expect(throws: UpdateError.newerFormat) { try UpdateFeed.decode(feed(files: [], format: UpdateFeed.format + 1)) }
    }

    @Test("路径越出应用包、块的下标对不上：不收", arguments: ["../evil", "/etc/evil", "Contents//x", "Contents/./x", ""])
    func rejectsBadPaths(path: String) {
        #expect(throws: UpdateError.self) {
            try UpdateFeed.decode(feed(files: [.init(path: path, executable: false, chunks: [])]))
        }
    }

    @Test("块的下标越界：不收")
    func rejectsBadIndex() {
        #expect(throws: UpdateError.self) {
            try UpdateFeed.decode(feed(files: [.init(path: "Contents/x", executable: false, chunks: [1])], chunks: [chunk]))
        }
    }

    @Test("比当前版本新的更新日志，新的在前")
    func releasesAfter() {
        let note = { (patch: Int) in ReleaseNote(version: Version(major: 2, minor: 1, patch: patch), date: "2026-11-2\(patch)",
                                                 title: "t\(patch)", body: "") }
        let package = UpdatePackage(file: "x.pack", chunking: Chunker.algorithm, chunks: [], files: [])
        let feed = UpdateFeed(version: Version(major: 2, minor: 1, patch: 3), releases: [note(3), note(2), note(1), note(0)],
                              package: package)
        #expect(feed.releases(after: Version(major: 2, minor: 1, patch: 1)).map(\.title) == ["t3", "t2"])
        #expect(feed.releases(after: Version(major: 2, minor: 1, patch: 3)).isEmpty)
    }
}

@Suite("更新日志 ReleaseNote")
struct ReleaseNoteTests {
    private let message = """
    Snug 2.0.1：修复远程约一分钟后手机屏被误移除

    修复
    - 主窗口停留在首页时，手机屏会被误判为断开并移除（#1）
    - 只采纳当前服务进程的记录

    其他
    - `--dump-uu` 输出各表格行的文字

    安装
    - 退出旧版后，下载 Snug-2.0.1.dmg，拖入「应用程序」替换即可

    感谢 @gaofeng21cn 定位这个问题（#2）。
    """

    @Test("标签说明 → 更新日志：第一行去掉「Snug 版本：」当标题，「安装」一节不要")
    func fromTag() {
        let note = ReleaseNote(version: Version(major: 2, minor: 0, patch: 1), date: "2026-11-14", tagMessage: message)
        #expect(note.title == "修复远程约一分钟后手机屏被误移除")
        #expect(!note.body.contains("安装"))
        #expect(!note.body.contains("dmg"))
        #expect(note.body.hasPrefix("修复\n- 主窗口"))
        #expect(note.body.hasSuffix("感谢 @gaofeng21cn 定位这个问题（#2）。"))
    }

    @Test("正文按行分成小标题、条目、段落：下一行是条目的那行算小标题")
    func blocks() {
        let note = ReleaseNote(version: Version(major: 2, minor: 0, patch: 1), date: "2026-11-14", tagMessage: message)
        #expect(note.blocks == [
            .heading("修复"),
            .bullet("主窗口停留在首页时，手机屏会被误判为断开并移除（#1）"),
            .bullet("只采纳当前服务进程的记录"),
            .heading("其他"),
            .bullet("`--dump-uu` 输出各表格行的文字"),
            .paragraph("感谢 @gaofeng21cn 定位这个问题（#2）。"),
        ])
    }

    @Test("没有正文、标题没带版本前缀的也认")
    func plain() {
        let note = ReleaseNote(version: Version(major: 2, minor: 2, patch: 0), date: "2026-12-01", tagMessage: "小修小补\n")
        #expect(note.title == "小修小补")
        #expect(note.body.isEmpty)
        #expect(note.blocks.isEmpty)
    }
}
