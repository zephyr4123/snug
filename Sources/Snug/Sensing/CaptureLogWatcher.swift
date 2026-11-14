// 推流信号：起一个 `/usr/bin/log stream` 子进程，只看 UURemoteServer 推流相关的几类日志，逐行交给 CaptureLogParser。
// 每次（重新）启动先用 `log show` 回看 replayWindow：UU 的常驻推流只在远程开头打一次「开始」，
// 远程中途打开 Snug（升级、崩溃后自启）或子进程重启时不回看，就会以为没在推。回看完成前推流状态报「未知」。
// 子进程挂了按退避重启（1→2→5→10→30→60s），跑满 60s 算稳定、退避清零；每次退出与重启都记日志。
// UURemoteServer 换了进程（崩溃重启），旧的推流状态作废：它崩溃时不会留下停流的日志。回看也只认当前进程打的日志。
// 没在跑的时候推流状态报「未知」（nil），连接判定照样靠覆盖窗口和控制端表格
import Foundation
import SnugCore

@MainActor
final class CaptureLogWatcher {
    static let restartDelays: [TimeInterval] = [1, 2, 5, 10, 30, 60]
    static let stableAfter: TimeInterval = 60
    static let streamArguments = ["stream", "--style", "ndjson", "--predicate", CaptureLogParser.predicate]
    /// 回看多久（实测 4 小时约 2 秒、几百行）。比这更早开始的远程，要等 UU 下一次开推（切屏）才认得出
    nonisolated static let replayWindow = "4h"
    nonisolated static let replayArguments = ["show", "--last", replayWindow, "--style", "ndjson", "--predicate", CaptureLogParser.predicate]

    private var process: Process?
    private var generation = 0
    private var failures = 0
    private var launchedAt = Date.distantPast
    private var wanted = false
    private var state = CaptureSessionState()
    /// 回看还没做完：这期间收到的实时记录先攒在这里
    private var buffered: [CaptureLogRecord]?
    private var serverPID: pid_t?

    private var isRunning: Bool { process?.isRunning ?? false }

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

    /// 此刻是否在推流、推的是哪块屏。active 为 nil = 未知：监听没在跑，或刚启动、还在回看
    func sample(at date: Date) -> (active: Bool?, display: DisplayID?) {
        guard isRunning, buffered == nil else { return (nil, nil) }
        noteServerProcess()
        return (state.isActive(at: date), state.streamingDisplay(at: date))
    }

    /// UURemoteServer 换了进程（或没了），旧的推流状态作废
    private func noteServerProcess() {
        let pid = UURemoteApp.serverPID()
        guard pid != serverPID else { return }
        if serverPID != nil {
            Log.warn("UURemoteServer 进程变了（\(serverPID.map(String.init) ?? "-") → \(pid.map(String.init) ?? "没在运行")），推流状态重来")
            state = CaptureSessionState()
        }
        serverPID = pid
    }

    private func launch() {
        generation += 1
        let gen = generation
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        p.arguments = Self.streamArguments
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        // readabilityHandler 不保证每次在同一个线程上回调
        let lines = Locked(CaptureLogLineBuffer())
        out.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            let records = lines.withLock { $0.feed(data) }
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
        buffered = []
        serverPID = UURemoteApp.serverPID()
        Log.info("推流日志监听已启动（log pid \(p.processIdentifier)\(failures > 0 ? "，第 \(failures) 次重启" : "")），回看 \(Self.replayWindow)")
        replay(generation: gen)
    }

    private func receive(_ records: [CaptureLogRecord], generation gen: Int) {
        guard gen == generation else { return }
        if buffered != nil {
            buffered?.append(contentsOf: records)
        } else {
            for r in records { state.apply(r) }
        }
    }

    /// 回看启动前的日志（log show 要一两秒，放在后台），做完接上这期间攒下的实时记录
    private func replay(generation gen: Int) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let history = Self.readHistory()
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.finishReplay(history, generation: gen) }
            }
        }
    }

    /// 回看失败返回 nil：照常只靠实时日志
    nonisolated private static func readHistory() -> [CaptureLogRecord]? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        p.arguments = replayArguments
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
        } catch {
            Log.warn("推流日志回看启动失败：\(error)")
            return nil
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            Log.warn("推流日志回看失败（状态 \(p.terminationStatus)）")
            return nil
        }
        var lines = CaptureLogLineBuffer()
        return lines.feed(data) + lines.finish()
    }

    private func finishReplay(_ history: [CaptureLogRecord]?, generation gen: Int) {
        guard gen == generation, let live = buffered else { return }
        buffered = nil
        state = CaptureSessionState.resumed(history: history ?? [], live: live, server: serverPID)
        let now = Date()
        let summary = state.isActive(at: now)
            ? "UU 正在推流（屏 \(state.streamingDisplay(at: now).map(String.init) ?? "未知")）" : "UU 没在推流"
        // 只数当前进程的：上一个进程的记录不参与回放，日志里要看得出来
        let mine = history.map { h in h.filter { serverPID != nil && $0.processID == serverPID }.count }
        Log.info("推流日志回看完成（\(history.map { "\($0.count) 条，当前 UURemoteServer 的 \(mine ?? 0) 条" } ?? "失败，只看实时日志")）：\(summary)")
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
