// 看门狗进程（--watchdog，由 launchd 托管）：兜底恢复被熄灭的物理屏。
// 判断全交给 WatchdogJudge，依据只有主程序写的 app-state.json（修 B3），恢复走 PhysicalDisplayLedger.restoreAll。
// 不起 NSApplication：没有窗口、没有主线程重配置通知，CG 事务直接在这个线程上做
import Darwin
import Foundation
import SnugCore
import SnugDisplays

enum WatchdogProcess {
    /// 原作者实测 1 秒间隔 CPU 约 0.2%，5 秒更省，代价是恢复最多慢几秒
    static let interval: TimeInterval = 5
    /// 恢复失败后的重试间隔上限（避免外接屏被拔掉时每 5 秒刷一次日志）
    static let maxRestoreBackoff: TimeInterval = 60

    static func run() -> Never {
        let paths = SnugPaths.standard
        let sink = FileLogSink(url: paths.logFile, processTag: "看门狗")
        Log.setSink(sink)
        installTermHandler(flushing: sink)
        Log.info("启动 pid=\(getpid())")

        var loop = WatchdogLoop(paths: paths)
        while true {
            autoreleasepool { loop.once(now: Date()) }
            Thread.sleep(forTimeInterval: interval)
        }
    }

    /// launchctl bootout 发 SIGTERM：写完日志再走
    private static func installTermHandler(flushing sink: FileLogSink) {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .global())
        source.setEventHandler {
            Log.info("收到 SIGTERM，退出")
            sink.flush()
            exit(0)
        }
        source.resume()
        termSource = source
    }

    nonisolated(unsafe) private static var termSource: (any DispatchSourceSignal)?
}

private struct WatchdogLoop {
    let paths: SnugPaths
    let ledger: PhysicalDisplayLedger
    let appState: JSONFile<AppStateRecord>
    var judge = WatchdogJudge()
    var restoreFailures = 0
    var nextRestoreAt = Date.distantPast
    var lastVerdict = WatchdogVerdict.idle

    init(paths: SnugPaths) {
        self.paths = paths
        ledger = PhysicalDisplayLedger(url: paths.disabledDisplays)
        appState = JSONFile(url: paths.appState)
    }

    mutating func once(now: Date) {
        beat()
        let verdict = judge.evaluate(observe(now: now), now: now)
        if verdict != lastVerdict, verdict == .idle { Log.info("回到待命") }
        lastVerdict = verdict
        switch verdict {
        case .idle:
            restoreFailures = 0
            nextRestoreAt = .distantPast
        case .restore(let reason):
            restore(reason: reason, now: now)
        case .killThenRestore(let pid, let reason):
            Log.warn("\(reason)，强制结束 pid=\(pid)")
            if kill(pid, SIGKILL) != 0 { Log.error("结束 pid=\(pid) 失败：errno \(errno)") }
            restore(reason: reason, now: now)
        }
    }

    private func observe(now: Date) -> WatchdogObservation {
        let record: AppStateRecord?
        switch appState.load() {
        case .loaded(let r): record = r
        case .missing: record = nil
        case .corrupt(let error):
            // 主程序原子写入，正常不会读到半截；读不出来按「主程序不在」处理
            Log.warn("app-state.json 读不出来：\(error)")
            record = nil
        }
        return WatchdogObservation(hasDisabledPhysical: !ledger.recorded().isEmpty,
                                   appState: record,
                                   heartbeatAge: modificationDate(paths.appState).map { now.timeIntervalSince($0) },
                                   appProcessAlive: record.map { isSnug(pid: $0.pid) } ?? false)
    }

    private mutating func restore(reason: WatchdogVerdict.Reason, now: Date) {
        guard now >= nextRestoreAt else { return }
        Log.info("按记录恢复物理屏（\(reason)）")
        let result = ledger.restoreAll(pause: DisplayTiming.settleAfterPhysical)
        if !result.restored.isEmpty { Log.info("已恢复物理屏 \(result.restored)") }
        guard !result.failed.isEmpty else {
            restoreFailures = 0
            nextRestoreAt = .distantPast
            return
        }
        restoreFailures += 1
        let wait = min(WatchdogProcess.interval * pow(2, Double(restoreFailures - 1)), WatchdogProcess.maxRestoreBackoff)
        nextRestoreAt = now.addingTimeInterval(wait)
        Log.warn("恢复物理屏 \(result.failed) 失败（\(result.failure.map { "\($0)" } ?? "未知错误")），\(Int(wait))s 后再试")
    }

    private func beat() {
        do {
            try FileManager.default.createDirectory(at: paths.dataDirectory, withIntermediateDirectories: true)
            try Data("\(getpid())".utf8).write(to: paths.watchdogHeartbeat, options: .atomic)
        } catch {
            Log.error("写看门狗心跳失败：\(error)")
        }
    }

    private func modificationDate(_ url: URL) -> Date? {
        var st = stat()
        guard stat(url.path, &st) == 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec) + TimeInterval(st.st_mtimespec.tv_nsec) / 1e9)
    }

    /// pid 还活着，而且确实是 Snug：pid 会被复用，不核对进程名就可能把一个无关的进程当成卡死的主程序结束掉
    private func isSnug(pid: Int32) -> Bool {
        guard pid > 0, kill(pid, 0) == 0 else { return false }
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return false }
        let path = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return URL(fileURLWithPath: path).lastPathComponent == "Snug"
    }
}
