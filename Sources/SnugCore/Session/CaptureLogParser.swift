// 解析 `log stream --style ndjson` 里 UURemoteServer 的推流与编码事件。
// 这些行来自 ScreenCaptureKit / VideoToolbox 的调试日志，格式不是公开接口，所以只认几条稳定的关键字，
// 认不出的行一律忽略；格式变了最多是推流信号变成「未知」，连接判定还有覆盖窗口和控制端表格兜底
import Foundation

public enum CaptureLogEvent: Equatable, Sendable {
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

public struct CaptureLogRecord: Equatable, Sendable {
    public let date: Date
    public let event: CaptureLogEvent

    public init(date: Date, event: CaptureLogEvent) {
        self.date = date
        self.event = event
    }
}

public struct CaptureLogParser {
    private let formatter: DateFormatter

    public init() {
        formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        // log 的 ndjson 时间戳形如 2026-11-12 19:01:43.417100-0800
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSSZ"
    }

    /// 一行 ndjson → 事件；不是 UURemoteServer 的、认不出的、非 JSON 的都返回 nil
    public func parse(line: String) -> CaptureLogRecord? {
        guard line.hasPrefix("{"),
              let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              let message = object["eventMessage"] as? String,
              let stamp = object["timestamp"] as? String,
              let date = formatter.date(from: stamp) else { return nil }
        if let process = object["processImagePath"] as? String, !process.hasSuffix("/" + UURemote.serverProcess) { return nil }
        return Self.classify(message).map { CaptureLogRecord(date: date, event: $0) }
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
