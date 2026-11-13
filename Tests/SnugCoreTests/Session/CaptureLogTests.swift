import Foundation
import Testing
@testable import SnugCore

/// 夹具来自 2026-11-12 本机 `log show --style ndjson --predicate 'process == "UURemoteServer" …'`，
/// 只保留时间、类型、子系统、进程路径和消息正文，不含 IP、用户名、主目录路径
private func fixture(_ name: String) throws -> [String] {
    guard let url = Bundle.module.url(forResource: "uuremoteserver-\(name)", withExtension: "ndjson", subdirectory: "Fixtures") else {
        throw CocoaError(.fileNoSuchFile)
    }
    return try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map(String.init)
}

/// 用和日志同样格式的字符串写断言里的时刻，一眼能对上夹具
private func ts(_ s: String) -> Date {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSZ"
    return f.date(from: "2026-11-12 \(s)-0800")!
}

/// 按时间顺序回放夹具，在每个探测时刻问一次「此刻是否在推流」（只用该时刻之前的日志）
private func activity(_ name: String, at probes: [String]) throws -> [String: Bool] {
    let parser = CaptureLogParser()
    var state = CaptureSessionState()
    var result: [String: Bool] = [:]
    var pending = probes
    for line in try fixture(name) {
        guard let record = parser.parse(line: line) else { continue }
        while let p = pending.first, ts(p) < record.date {
            result[p] = state.isActive(at: ts(p))
            pending.removeFirst()
        }
        state.apply(record)
    }
    for p in pending { result[p] = state.isActive(at: ts(p)) }
    return result
}

private func message(_ text: String, process: String = "/Applications/UURemote.app/Contents/Helpers/UURemoteServer",
                     at time: String = "19:01:43.417100") -> String {
    let obj: [String: String] = ["timestamp": "2026-11-12 \(time)-0800", "processImagePath": process, "eventMessage": text]
    return String(decoding: try! JSONSerialization.data(withJSONObject: obj), as: UTF8.self)
}

private func scDisplay(_ id: Int) -> String {
    " [INFO] -[SCDisplay initWithDict:]:196 (0x1) displayID=\(id) frame=(0.000000,0.000000,1320.000000,2868.000000) width=1320 height=2868"
}

private let startCapture = " [INFO] -[SCStream startCaptureWithCompletionHandler:]:939 0x1 streamID=<private>"
private let stopCapture = " [INFO] -[SCStream stopCaptureWithCompletionHandler:]:983 0x1 streamID=<private>"

@Suite("推流日志 CaptureLogParser / CaptureSessionState")
struct CaptureLogTests {
    @Test("逐类识别 UURemoteServer 的行")
    func classify() {
        let p = CaptureLogParser()
        #expect(p.parse(line: message(" [INFO] -[SCStream startCaptureWithCompletionHandler:]:939 0x1 streamID=<private>"))?.event == .captureStarted)
        #expect(p.parse(line: message(" [INFO] -[SCStream stopCaptureWithCompletionHandler:]:983 0x1 streamID=<private>"))?.event == .captureStopped)
        #expect(p.parse(line: message(" [INFO] _SCStream_UpdateAndHandleFrameStatus:1729 Stopping stream due to stream frameStatus=7"))?.event == .captureStopped)
        #expect(p.parse(line: message("<<<< VT-CS >>>> VTCompressionSessionCreateWithOptions: [0x1:CS/ZDF] new compression session (primary-session): codec hvc1"))?.event == .encoderCreated)
        #expect(p.parse(line: message("<<<< VT-CS >>>> VTCompressionSessionInvalidate: [0x1:CS/ZDF] invalidating compression session: encoded 750 dropped 0 duration 19581 [ms]"))?.event
                == .encoderEnded(encoded: 750, dropped: 0, durationMs: 19581))
        #expect(p.parse(line: message("<<<< VT-CS >>>> VTCompressionSessionInvalidate: [0x1:CS/HQO] invalidating compression session"))?.event == .encoderProbeEnded)
    }

    @Test("不相干的行一律忽略：停流回调的报错行、别的进程、非 JSON、log 的结尾统计")
    func ignores() {
        let p = CaptureLogParser()
        #expect(p.parse(line: message(" [ERROR] -[SCStream stopCaptureWithCompletionHandler:]_block_invoke_2:995 error=Error Domain=x Code=-3808")) == nil)
        #expect(p.parse(line: message(" [INFO] -[SCStream startCaptureWithCompletionHandler:]:939 0x1", process: "/usr/libexec/other")) == nil)
        #expect(p.parse(line: "Filtering the log data using \"process == UURemoteServer\"") == nil)
        #expect(p.parse(line: #"{"count":28,"finished":1}"#) == nil)
        #expect(p.parse(line: message("CGSDisplayNotifyProc: got notification kCGSDisplayWillReconfigure")) == nil)
    }

    @Test("时间戳按日志自带的时区解析")
    func timestamp() {
        let r = CaptureLogParser().parse(line: message(" [INFO] -[SCStream startCaptureWithCompletionHandler:]:939 0x1"))
        #expect(r?.date == ts("19:01:43.417"))
    }

    @Test("19:01 夹具：推流从 02.387 开始，关物理屏时停流重建、编码会话中途重建都不算结束，43.417 结束后 3s 判停")
    func replay1901() throws {
        #expect(CaptureSessionState.restartGrace == 3)
        let a = try activity("1901", at: ["19:01:02.300", "19:01:02.500", "19:01:23.700", "19:01:27.000",
                                         "19:01:43.000", "19:01:46.400", "19:01:46.500"])
        #expect(a["19:01:02.300"] == false)
        #expect(a["19:01:02.500"] == true)
        #expect(a["19:01:23.700"] == true)   // 23.405 停流 → 23.527 新编码会话 → 23.561 重新推流
        #expect(a["19:01:27.000"] == true)   // 23.822 编码会话带摘要结束，23.831 新编码会话接上（没有新的推流开始）
        #expect(a["19:01:43.000"] == true)
        #expect(a["19:01:46.400"] == true)   // 43.417 + 3 = 46.417
        #expect(a["19:01:46.500"] == false)
    }

    @Test("17:55 夹具：5 分钟长会话里 17:56:34 编码会话重建，不能判停")
    func replay1755() throws {
        let a = try activity("1755", at: ["17:56:40.000", "18:00:00.000", "18:00:55.300", "18:00:55.400"])
        #expect(a["17:56:40.000"] == true)
        #expect(a["18:00:00.000"] == true)
        #expect(a["18:00:55.300"] == true)   // 52.366 + 3 = 55.366
        #expect(a["18:00:55.400"] == false)
    }

    @Test("20:00 夹具：两段会话中间的空档判停，第二段重新开始")
    func replay2000() throws {
        let a = try activity("2000", at: ["20:00:42.000", "20:01:00.000", "20:01:06.700", "20:01:06.800", "20:01:15.000",
                                         "20:01:21.500", "20:01:40.000", "20:01:59.100", "20:01:59.300"])
        #expect(a["20:00:42.000"] == true)
        #expect(a["20:01:00.000"] == true)
        #expect(a["20:01:06.700"] == true)    // 03.774 + 3 = 06.774
        #expect(a["20:01:06.800"] == false)
        #expect(a["20:01:15.000"] == false)
        #expect(a["20:01:21.500"] == true)
        #expect(a["20:01:40.000"] == true)
        #expect(a["20:01:59.100"] == true)    // 56.206 + 3 = 59.206
        #expect(a["20:01:59.300"] == false)
    }

    @Test("SCDisplay initWithDict 的 displayID 解析成「描述了哪块屏」")
    func describesDisplay() {
        let p = CaptureLogParser()
        #expect(p.parse(line: message(scDisplay(14)))?.event == .displayDescribed(14))
        #expect(p.parse(line: message(" [INFO] -[SCDisplay initWithDict:]:196 (0x1) frame=(0,0,1,1)")) == nil)
    }

    @Test("UU 在推哪块屏：推流开始前最后描述的那块；中途枚举别的屏不改；停流过了宽限就清空")
    func streamingDisplay() {
        // 形态取自 2026-11-12 20:00:41–44 与 20:01:03 的真实日志：先枚举 1、14，再为 1 建过滤器并开推；
        // 关屏后停流，枚举 14、为 14 建过滤器并开推；20:01:03.772 停流
        let lines = [
            ("20:00:41.830000", scDisplay(1)), ("20:00:41.830100", scDisplay(14)), ("20:00:41.831000", scDisplay(1)),
            ("20:00:41.831500", startCapture),
            ("20:00:43.940000", stopCapture),
            ("20:00:44.046000", scDisplay(14)), ("20:00:44.075000", scDisplay(14)),
            ("20:00:44.075500", startCapture),
            ("20:00:50.000000", scDisplay(1)),
            ("20:01:03.772000", stopCapture),
        ]
        let p = CaptureLogParser()
        var s = CaptureSessionState()
        var seen: [String: DisplayID?] = [:]
        func probe(_ t: String) { seen[t] = s.streamingDisplay(at: ts(t)) }
        probe("20:00:41.000")
        for (time, text) in lines {
            if time == "20:00:43.940000" { probe("20:00:43.000") }
            if time == "20:00:50.000000" { probe("20:00:49.000") }
            guard let r = p.parse(line: message(text, at: time)) else { continue }
            s.apply(r)
        }
        probe("20:01:00.000")
        probe("20:01:06.700")
        probe("20:01:06.800")
        #expect(seen["20:00:41.000"] == .some(nil))
        #expect(seen["20:00:43.000"] == .some(1))
        #expect(seen["20:00:49.000"] == .some(14))
        #expect(seen["20:01:00.000"] == .some(14))   // 50.000 枚举了 1，不算换屏
        #expect(seen["20:01:06.700"] == .some(14))   // 03.772 + 3 = 06.772 之前仍在宽限里
        #expect(seen["20:01:06.800"] == .some(nil))
    }

    @Test("只有探测性编码会话（没有推流开始）不会让状态变成推流中")
    func probesAloneStayInactive() {
        var s = CaptureSessionState()
        let d = ts("16:50:00.000")
        s.apply(CaptureLogRecord(date: d, event: .encoderCreated))
        s.apply(CaptureLogRecord(date: d, event: .encoderProbeEnded))
        #expect(!s.isActive(at: d.addingTimeInterval(1)))
    }
}
