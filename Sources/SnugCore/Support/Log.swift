// 日志：写 os.Logger（subsystem com.zephyr4123.snug），同时镜像到可替换的 sink（正式运行是日志文件，测试里关掉）
import Foundation
import os

public enum LogLevel: String, Sendable {
    case debug, info, warn, error
}

public protocol LogSink: Sendable {
    func write(_ level: LogLevel, _ message: String, at date: Date)
}

public enum Log {
    public static let subsystem = "com.zephyr4123.snug"

    private static let logger = Logger(subsystem: subsystem, category: "snug")
    private static let sink = Locked<(any LogSink)?>(nil)

    /// 替换镜像目标；nil 表示只写 os.Logger
    public static func setSink(_ newSink: (any LogSink)?) {
        sink.withLock { $0 = newSink }
    }

    public static func debug(_ message: String) { emit(.debug, message) }
    public static func info(_ message: String) { emit(.info, message) }
    public static func warn(_ message: String) { emit(.warn, message) }
    public static func error(_ message: String) { emit(.error, message) }

    private static func emit(_ level: LogLevel, _ message: String) {
        switch level {
        case .debug: logger.debug("\(message, privacy: .public)")
        case .info: logger.info("\(message, privacy: .public)")
        case .warn: logger.warning("\(message, privacy: .public)")
        case .error: logger.error("\(message, privacy: .public)")
        }
        sink.withLock { $0 }?.write(level, message, at: Date())
    }
}
