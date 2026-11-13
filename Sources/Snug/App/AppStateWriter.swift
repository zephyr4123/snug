// app-state.json：主程序每秒写一次，看门狗只认它（修 B3）。mtime 即心跳。
// 由主线程的定时器发起（主线程卡死就停跳，看门狗才能发现），写盘放后台串行队列，不卡主线程
import Foundation
import SnugCore

@MainActor
final class AppStateWriter {
    private let file: JSONFile<AppStateRecord>
    private let queue = DispatchQueue(label: "com.zephyr4123.snug.app-state", qos: .utility)
    private let failing = FailureLatch()

    init(url: URL) { file = JSONFile(url: url) }

    func write(connected: Bool, keepOnlyVirtualActive: Bool) {
        let record = AppStateRecord(pid: getpid(), updatedAt: Date(), connected: connected,
                                    keepOnlyVirtualActive: keepOnlyVirtualActive)
        let file = file, failing = failing
        queue.async {
            do {
                try file.save(record)
                if failing.clear() { Log.info("app-state.json 恢复写入") }
            } catch {
                // 每秒都写，只在第一次失败时记一条，免得刷屏
                if failing.set() { Log.error("写 app-state.json 失败，看门狗会以为主程序卡住：\(error)") }
            }
        }
    }
}

/// 记住「上一次是否失败」，只在状态翻转时返回 true。只在 AppStateWriter 的串行队列上用
private final class FailureLatch: @unchecked Sendable {
    private var failed = false

    func set() -> Bool {
        defer { failed = true }
        return !failed
    }

    func clear() -> Bool {
        defer { failed = false }
        return failed
    }
}
