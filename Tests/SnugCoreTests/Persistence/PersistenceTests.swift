import Foundation
import Testing
@testable import SnugCore

private struct Sample: Codable, Equatable { var name: String; var count: Int }

@Suite("持久化")
struct PersistenceTests {
    @Test("SnugPaths：数据目录与各状态文件的名字")
    func pathNames() {
        let p = SnugPaths(dataDirectory: URL(fileURLWithPath: "/d"), logFile: URL(fileURLWithPath: "/l/Snug.log"))
        #expect(p.config.path == "/d/config.json")
        #expect(p.phoneRecord.path == "/d/phone-screen.json")
        #expect(p.zoomBook.path == "/d/zoom.json")
        #expect(SnugPaths.standard.dataDirectory.path.hasSuffix("Library/Application Support/Snug"))
        #expect(SnugPaths.standard.logFile.path.hasSuffix("Library/Logs/Snug.log"))
    }

    @Test("JSONFile.load 区分不存在 / 损坏 / 成功")
    func loadStates() throws {
        let dir = try TempDir()
        let file = JSONFile<Sample>(url: dir.url.appendingPathComponent("s.json"))
        guard case .missing = file.load() else { Issue.record("不存在的文件应返回 .missing"); return }

        try file.save(Sample(name: "a", count: 1))
        guard case .loaded(let v) = file.load() else { Issue.record("应能读回"); return }
        #expect(v == Sample(name: "a", count: 1))

        try Data("{not json".utf8).write(to: file.url)
        guard case .corrupt = file.load() else { Issue.record("坏 JSON 应返回 .corrupt"); return }
    }

    @Test("save 写不进去会 throw；remove 对不存在的文件不报错，对删不掉的会 throw")
    func saveAndRemoveThrow() throws {
        let dir = try TempDir()
        // 父路径是个普通文件，目录建不出来
        let blocker = dir.url.appendingPathComponent("blocker")
        try Data().write(to: blocker)
        let bad = JSONFile<Sample>(url: blocker.appendingPathComponent("x.json"))
        #expect(throws: (any Error).self) { try bad.save(Sample(name: "a", count: 1)) }

        let file = JSONFile<Sample>(url: dir.url.appendingPathComponent("s.json"))
        try file.remove()
        try file.save(Sample(name: "a", count: 1))
        try file.remove()
        guard case .missing = file.load() else { Issue.record("删除后应不存在"); return }

        // 只读目录里的文件删不掉
        let locked = dir.url.appendingPathComponent("locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        let inLocked = JSONFile<Sample>(url: locked.appendingPathComponent("s.json"))
        try inLocked.save(Sample(name: "b", count: 2))
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: locked.path) }
        #expect(throws: (any Error).self) { try inLocked.remove() }
    }

    @Test("损坏的文件改名成 <name>.corrupt-<时间戳>.json，原位置空出来")
    func quarantine() throws {
        let dir = try TempDir()
        let file = JSONFile<Sample>(url: dir.url.appendingPathComponent("config.json"))
        try Data("garbage".utf8).write(to: file.url)
        var c = DateComponents()
        (c.year, c.month, c.day, c.hour, c.minute, c.second) = (2026, 11, 12, 19, 30, 5)
        let when = Calendar.current.date(from: c)!
        let moved = try file.quarantine(now: when)
        #expect(moved.lastPathComponent.hasPrefix("config.corrupt-20261112-193005"))
        #expect(moved.pathExtension == "json")
        #expect(FileManager.default.fileExists(atPath: moved.path))
        #expect(!FileManager.default.fileExists(atPath: file.url.path))
        #expect(try String(contentsOf: moved, encoding: .utf8) == "garbage")
    }

    @Test("loadOrQuarantine：损坏时隔离原文件并返回 nil，不覆盖原内容")
    func loadOrQuarantine() throws {
        let dir = try TempDir()
        let file = JSONFile<Sample>(url: dir.url.appendingPathComponent("config.json"))
        #expect(file.loadOrQuarantine() == nil)
        try Data("garbage".utf8).write(to: file.url)
        #expect(file.loadOrQuarantine() == nil)
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.url.path)
        #expect(names.count == 1)
        #expect(names[0].hasPrefix("config.corrupt-"))
    }

    @Test("RestoreRecord：先记账、有待还原的记录、还原成功才销账")
    func restoreRecord() throws {
        let dir = try TempDir()
        let record = RestoreRecord<Sample>(url: dir.url.appendingPathComponent("r.json"))
        #expect(record.pending() == nil)
        try record.record(Sample(name: "before", count: 3))
        #expect(record.pending() == Sample(name: "before", count: 3))
        try record.settle()
        #expect(record.pending() == nil)
    }
}
