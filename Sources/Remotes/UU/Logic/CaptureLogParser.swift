// 解析 `log stream --style ndjson` 里 UURemoteServer 的推流与编码事件。
// 这些行来自 ScreenCaptureKit / VideoToolbox 的调试日志，格式不是公开接口，所以只认几条稳定的关键字，
// 认不出的行一律忽略。格式变了，认不出开始事件时推流信号缺席，认不出停止事件时推流会一直显示在进行，后果见 ConnectionTracker
import Foundation
import SnugCore

package enum CaptureLogEvent: Equatable, Sendable {
    /// -[SCDisplay initWithDict:] … displayID=N：ScreenCaptureKit 描述了一块屏。
    /// UU 枚举全部屏幕时每块都会出现一次，为要推的那块建过滤器时再出现一次，紧接着推流开始
    case displayDescribed(DisplayID)
    /// -[SCStream startCaptureWithCompletionHandler:]
    case captureStarted
    /// -[SCStream stopCaptureWithCompletionHandler:] 或「Stopping stream due to stream frameStatus」
    case captureStopped
    /// VTCompressionSessionCreateWithOptions：新建编码会话
    case encoderCreated
    /// 编码会话结束，带「encoded N dropped M duration D [ms]」摘要：真正推过流的会话
    case encoderEnded(encoded: Int, dropped: Int, durationMs: Int)
    /// 编码会话结束但没有摘要：UU 试探编码参数时建了就扔的会话，不代表推流结束
    case encoderProbeEnded
}

package struct CaptureLogRecord: Equatable, Sendable {
    package let date: Date
    package let event: CaptureLogEvent
    /// 打这条日志的 UURemoteServer 进程号；读不到为 nil
    package let processID: pid_t?

    /// streamID 常被系统隐去，但同一进程内的 SCStream 对象地址仍可用于配对。
    let streamAddress: UInt64?

    package init(date: Date, event: CaptureLogEvent, processID: pid_t? = nil, streamAddress: UInt64? = nil) {
        self.date = date
        self.event = event
        self.processID = processID
        self.streamAddress = streamAddress
    }
}

package struct CaptureLogParser {
    /// classify 认的几类行都含其中一个词。log 子进程按它过滤：Snug 少收、少解析，回看几个小时的日志也只有几百行
    static let keywords = ["SCDisplay initWithDict:", "CaptureWithCompletionHandler:]", "Stopping stream due to", "VTCompressionSession"]
    /// `log stream` / `log show` 的 --predicate
    package static let predicate = "process == \"\(UURemote.serverProcess)\" AND ("
        + keywords.map { "eventMessage CONTAINS \"\($0)\"" }.joined(separator: " OR ") + ")"

    private let formatter: DateFormatter

    package init() {
        formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        // log 的 ndjson 时间戳形如 2026-11-12 19:01:43.417100-0800
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSSZ"
    }

    /// 一行 ndjson → 事件；不是 UURemoteServer 的、认不出的、非 JSON 的都返回 nil
    package func parse(line: String) -> CaptureLogRecord? {
        guard line.hasPrefix("{"),
              let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              let message = object["eventMessage"] as? String,
              let stamp = object["timestamp"] as? String,
              let date = formatter.date(from: stamp) else { return nil }
        if let process = object["processImagePath"] as? String, !process.hasSuffix("/" + UURemote.serverProcess) { return nil }
        let processID = (object["processID"] as? Int).flatMap(pid_t.init(exactly:))
        guard let event = Self.classify(message) else { return nil }
        let streamAddress: UInt64?
        switch event {
        case .captureStarted, .captureStopped:
            streamAddress = message.range(of: " 0x").flatMap { address in
                UInt64(message[address.upperBound...].prefix(while: \.isHexDigit), radix: 16)
            }
        default:
            streamAddress = nil
        }
        return CaptureLogRecord(date: date, event: event, processID: processID, streamAddress: streamAddress)
    }

    static func classify(_ message: String) -> CaptureLogEvent? {
        if message.contains("SCDisplay initWithDict:") { return displayID(in: message).map { .displayDescribed($0) } }
        if message.contains("startCaptureWithCompletionHandler:]") { return .captureStarted }
        // 「…stopCaptureWithCompletionHandler:]_block_invoke_2…error=」是停流回调里的报错，同一次停流已经记过
        if message.contains("stopCaptureWithCompletionHandler:]:") { return .captureStopped }
        if message.contains("Stopping stream due to") { return .captureStopped }
        if message.contains("VTCompressionSessionCreate") { return .encoderCreated }
        guard message.contains("VTCompressionSessionInvalidate") else { return nil }
        guard let summary = message.range(of: "encoded ") else { return .encoderProbeEnded }
        let numbers = message[summary.lowerBound...].split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard numbers.count >= 3 else { return .encoderProbeEnded }
        return .encoderEnded(encoded: numbers[0], dropped: numbers[1], durationMs: numbers[2])
    }

    private static func displayID(in message: String) -> DisplayID? {
        guard let key = message.range(of: "displayID=") else { return nil }
        return DisplayID(message[key.upperBound...].prefix { $0.isNumber })
    }
}

/// 把 log 子进程的输出切成行再解析：一行常被切在两块数据里，按字节攒到换行再解码（先解码会把切在中间的汉字解坏）
package struct CaptureLogLineBuffer {
    private var pending = Data()
    private let parser = CaptureLogParser()

    package init() {}

    package mutating func feed(_ data: Data) -> [CaptureLogRecord] {
        pending.append(data)
        var records: [CaptureLogRecord] = []
        while let newline = pending.firstIndex(of: 0x0A) {
            if let r = parse(pending[pending.startIndex..<newline]) { records.append(r) }
            pending.removeSubrange(pending.startIndex...newline)
        }
        return records
    }

    /// 输出结束：最后一行可能没有换行
    package mutating func finish() -> [CaptureLogRecord] {
        defer { pending.removeAll() }
        return parse(pending).map { [$0] } ?? []
    }

    private func parse(_ line: Data) -> CaptureLogRecord? {
        parser.parse(line: String(decoding: line, as: UTF8.self))
    }
}
