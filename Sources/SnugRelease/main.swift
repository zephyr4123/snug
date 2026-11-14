// snug-release：发版时打更新包、写 update.json。只由 scripts/snug 调：
//   snug-release pack <应用包> <版本> <目录>   dist：把公证过的 Snug.app 打成 Snug-<版本>.pack 和清单 update-package.json，
//                                              再照清单拼一遍、核对签名，不过就不交
//   snug-release feed <版本> <目录>            ship：清单加上各版本的更新日志（取自标签说明），写成 update.json。
//                                              放在 ship 而不是 dist：先打包、后打标签时，dist 那会儿还没有这一版的说明
import Foundation
import SnugCore

/// 应用内更新从这一版起才有。更早的版本自己不会检查更新，它们的更新日志不用放进 update.json
let firstUpdatable = Version(major: 2, minor: 1, patch: 0)
let manifestName = "update-package.json"

struct Failure: Error, CustomStringConvertible {
    let description: String
}

let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return encoder
}()

func pack(app: URL, version: Version, into dir: URL) throws {
    let name = "Snug-\(version).pack"
    let (package, data) = try UpdatePackage.make(app: app, file: name)
    // 照清单从包里拼一遍，核对拼出来的签名：客户端更新时验收的就是这一条。
    // 包格式只记普通文件的内容和可执行位，应用包里要是有它记不下的东西（扩展属性、空目录），这里就过不了
    let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("snug-release-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: scratch) }
    let assembled = scratch.appendingPathComponent("Snug.app")
    try package.assemble(into: assembled, from: package.unpack(data, at: 0..<data.count))
    try run("codesign", "--verify", "--strict", "--deep", assembled.path)
    try data.write(to: dir.appendingPathComponent(name))
    try encoder.encode(package).write(to: dir.appendingPathComponent(manifestName))
    let size = ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
    print("更新包 \(name)：\(package.files.count) 个文件、\(package.chunks.count) 块、\(size)，照清单拼过一遍，签名核对通过")
}

func feed(version: Version, dir: URL) throws {
    let package = try JSONDecoder().decode(UpdatePackage.self, from: Data(contentsOf: dir.appendingPathComponent(manifestName)))
    let versions = try run("git", "tag", "--list", "v*").split(separator: "\n").compactMap { Version(String($0.dropFirst())) }
    let releases = try versions.filter { $0 >= firstUpdatable && $0 <= version }.sorted(by: >).map { v in
        ReleaseNote(version: v, date: try run("git", "tag", "--list", "--format=%(taggerdate:short)", "v\(v)"),
                    tagMessage: try run("git", "tag", "--list", "--format=%(contents)", "v\(v)"))
    }
    guard releases.first?.version == version else { throw Failure(description: "没有标签 v\(version)，更新日志取自标签说明") }
    let feed = UpdateFeed(version: version, releases: releases, package: package)
    try encoder.encode(feed).write(to: dir.appendingPathComponent("update.json"))
    print("update.json：\(version)，更新日志 \(releases.count) 版（\(releases.map(\.version.description).joined(separator: "、"))）")
}

/// 跑一个命令行工具，交回它的输出；退出码不是 0 就把它说的话带进错误
@discardableResult
func run(_ tool: String, _ arguments: String...) throws -> String {
    let process = Process()
    let output = Pipe(), errors = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [tool] + arguments
    process.standardOutput = output
    process.standardError = errors
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    let said = errors.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw Failure(description: "\(tool) \(arguments.joined(separator: " ")) 退出码 \(process.terminationStatus)："
            + String(decoding: said, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }
    return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
}

let usage = """
用法：snug-release pack <应用包> <版本> <目录>
      snug-release feed <版本> <目录>
"""

let arguments = Array(CommandLine.arguments.dropFirst())
do {
    switch (arguments.first, arguments.count) {
    case ("pack", 4):
        guard let version = Version(arguments[2]) else { throw Failure(description: "版本号不对：\(arguments[2])") }
        try pack(app: URL(fileURLWithPath: arguments[1]), version: version, into: URL(fileURLWithPath: arguments[3]))
    case ("feed", 3):
        guard let version = Version(arguments[1]) else { throw Failure(description: "版本号不对：\(arguments[1])") }
        try feed(version: version, dir: URL(fileURLWithPath: arguments[2]))
    default:
        FileHandle.standardError.write(Data("\(usage)\n".utf8))
        exit(2)
    }
} catch {
    FileHandle.standardError.write(Data("❌ snug-release：\(error)\n".utf8))
    exit(1)
}
