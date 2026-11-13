import Foundation
import Testing
@testable import SnugCore

private func lines(_ url: URL) throws -> [String] {
    try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map(String.init)
}

@Suite("日志")
struct FileLogSinkTests {
    @Test("追加写入，行里带时间、级别和消息")
    func appends() throws {
        let dir = try TempDir()
        let url = dir.url.appendingPathComponent("Snug.log")
        let sink = FileLogSink(url: url)
        sink.write(.info, "第一行", at: Date())
        sink.write(.warn, "第二行", at: Date())
        sink.flush()
        let got = try lines(url)
        #expect(got.count == 2)
        #expect(got[0].contains("[info] 第一行"))
        #expect(got[1].contains("[warn] 第二行"))
        #expect(got[0].hasPrefix("[20"))
    }

    @Test("帮手进程的行带 [帮手] 标记")
    func processTag() throws {
        let dir = try TempDir()
        let url = dir.url.appendingPathComponent("Snug.log")
        let sink = FileLogSink(url: url, processTag: "帮手")
        sink.write(.error, "切模式失败", at: Date())
        sink.flush()
        #expect(try lines(url).count == 1)
        #expect(try lines(url)[0].contains("[error] [帮手] 切模式失败"))
    }

    @Test("两个写入者同时写同一个文件（模拟主程序 + 帮手进程）：400 行一行不丢、不串")
    func concurrentWriters() async throws {
        let dir = try TempDir()
        let url = dir.url.appendingPathComponent("Snug.log")
        let a = FileLogSink(url: url)
        let b = FileLogSink(url: url, processTag: "帮手")
        await withTaskGroup(of: Void.self) { group in
            group.addTask { for i in 0..<200 { a.write(.info, "A-\(i)", at: Date()) } }
            group.addTask { for i in 0..<200 { b.write(.info, "B-\(i)", at: Date()) } }
        }
        a.flush()
        b.flush()
        let got = try lines(url)
        #expect(got.count == 400)
        #expect(got.filter { $0.contains("] A-") }.count == 200)
        #expect(got.filter { $0.contains("[帮手] B-") }.count == 200)
    }

    @Test("超过上限滚动一份 .1，旧的 .1 被覆盖")
    func rotation() throws {
        let dir = try TempDir()
        let url = dir.url.appendingPathComponent("Snug.log")
        let rotated = dir.url.appendingPathComponent("Snug.log.1")
        let sink = FileLogSink(url: url, maxBytes: 200)
        for i in 0..<20 { sink.write(.info, "line-\(i)-xxxxxxxxxxxxxxxxxxxx", at: Date()) }
        sink.flush()
        #expect(FileManager.default.fileExists(atPath: rotated.path))
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0
        #expect(size < 200 + 80)
        // 最后一行一定在当前文件里
        #expect(try lines(url).last?.contains("line-19-") == true)
    }

    @Test("文件打不开时不崩溃，后续写入照常返回")
    func failureDoesNotCrash() {
        let sink = FileLogSink(url: URL(fileURLWithPath: "/dev/null/not-a-dir/Snug.log"))
        sink.write(.error, "写不进去", at: Date())
        sink.write(.info, "还是写不进去", at: Date())
        sink.flush()
    }
}

/// 只有这个用例替换全局 sink；其他用例产生的日志也可能落进来，所以只断言「包含」
@Suite("全局 Log", .serialized)
struct GlobalLogTests {
    final class Capture: LogSink, @unchecked Sendable {
        private let lock = NSLock()
        private var items: [(LogLevel, String)] = []
        func write(_ level: LogLevel, _ message: String, at date: Date) {
            lock.lock(); items.append((level, message)); lock.unlock()
        }
        func contains(_ level: LogLevel, _ text: String) -> Bool {
            lock.lock(); defer { lock.unlock() }
            return items.contains { $0.0 == level && $0.1 == text }
        }
    }

    @Test("四个级别都转给 sink；sink 设为 nil 后不再转")
    func levels() {
        let cap = Capture()
        Log.setSink(cap)
        defer { Log.setSink(nil) }
        let tag = UUID().uuidString
        Log.debug("d\(tag)")
        Log.info("i\(tag)")
        Log.warn("w\(tag)")
        Log.error("e\(tag)")
        #expect(cap.contains(.debug, "d\(tag)"))
        #expect(cap.contains(.info, "i\(tag)"))
        #expect(cap.contains(.warn, "w\(tag)"))
        #expect(cap.contains(.error, "e\(tag)"))
        Log.setSink(nil)
        Log.info("after\(tag)")
        #expect(!cap.contains(.info, "after\(tag)"))
    }
}
