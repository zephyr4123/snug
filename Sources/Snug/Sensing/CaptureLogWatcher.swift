// 推流信号：起一个 `/usr/bin/log stream` 子进程，只看 UURemoteServer 的日志，逐行交给 CaptureLogParser。
// 子进程挂了按退避重启（1→2→5→10→30→60s），跑满 60s 算稳定、退避清零；每次退出与重启都记日志。
// 没在跑的时候推流状态报「未知」（nil），连接判定照样靠覆盖窗口和控制端表格
import Foundation
import SnugCore

@MainActor
final class CaptureLogWatcher {
    static let restartDelays: [TimeInterval] = [1, 2, 5, 10, 30, 60]
    static let stableAfter: TimeInterval = 60
    static let arguments = ["stream", "--style", "ndjson", "--predicate", "process == \"\(UURemote.serverProcess)\""]

    private var process: Process?
    private var generation = 0
    private var failures = 0
    private var launchedAt = Date.distantPast
    private var wanted = false
    private var state = CaptureSessionState()

    var isRunning: Bool { process?.isRunning ?? false }

    func start() {
        guard !wanted else { return }
        wanted = true
        launch()
    }

    func stop() {
        wanted = false
        generation += 1
        if let p = process, p.isRunning { p.terminate() }
        process = nil
    }

    /// nil = 监听没在跑，推流状态未知
    func captureActive(at date: Date) -> Bool? {
        isRunning ? state.isActive(at: date) : nil
    }

    func streamingDisplay(at date: Date) -> DisplayID? {
        isRunning ? state.streamingDisplay(at: date) : nil
    }

    private func launch() {
        generation += 1
        let gen = generation
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        p.arguments = Self.arguments
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        let decoder = LogLineDecoder()
        out.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            let records = decoder.feed(data)
            guard !records.isEmpty else { return }
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.receive(records, generation: gen) }
            }
        }
        p.terminationHandler = { [weak self] proc in
            let status = proc.terminationStatus
            let stderr = String(decoding: err.fileHandleForReading.availableData.prefix(300), as: UTF8.self)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.exited(status: status, stderr: stderr, generation: gen) }
            }
        }
        do {
            try p.run()
        } catch {
            Log.error("推流日志监听启动失败：\(error)")
            process = nil
            scheduleRestart(generation: gen)
            return
        }
        process = p
        launchedAt = Date()
        state = CaptureSessionState()
        Log.info("推流日志监听已启动（log pid \(p.processIdentifier)\(failures > 0 ? "，第 \(failures) 次重启" : "")）")
    }

    private func receive(_ records: [CaptureLogRecord], generation gen: Int) {
        guard gen == generation else { return }
        for r in records { state.apply(r) }
    }

    private func exited(status: Int32, stderr: String, generation gen: Int) {
        guard gen == generation, wanted else { return }
        process = nil
        let ran = Date().timeIntervalSince(launchedAt)
        let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        Log.warn(String(format: "推流日志监听退出（状态 %d，跑了 %.0fs）", status, ran) + (detail.isEmpty ? "" : "：\(detail)"))
        scheduleRestart(generation: gen, ranFor: ran)
    }

    private func scheduleRestart(generation gen: Int, ranFor ran: TimeInterval = 0) {
        failures = ran >= Self.stableAfter ? 1 : failures + 1
        let delay = Self.restartDelays[min(failures, Self.restartDelays.count) - 1]
        Log.info("推流日志监听 \(Int(delay))s 后第 \(failures) 次重启")
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.wanted, self.generation == gen else { return }
                self.launch()
            }
        }
    }
}

/// 把子进程输出切成行再解析。只在 readabilityHandler 里调用；FileHandle 不保证回调线程固定，所以加锁
private final class LogLineDecoder: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private let parser = CaptureLogParser()

    func feed(_ data: Data) -> [CaptureLogRecord] {
        lock.lock()
        defer { lock.unlock() }
        buffer.append(data)
        var records: [CaptureLogRecord] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = String(decoding: buffer[buffer.startIndex..<newline], as: UTF8.self)
            buffer.removeSubrange(buffer.startIndex...newline)
            if let r = parser.parse(line: line) { records.append(r) }
        }
        return records
    }
}
