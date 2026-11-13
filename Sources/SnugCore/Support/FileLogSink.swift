// 日志文件镜像。主程序和看门狗两个进程写同一个文件，所以：
// - 只用 O_APPEND 打开一次并持有句柄：每次 write 由内核原子追加到末尾，两个进程不会互相覆盖行
//   （旧版每行重新打开、seek 到末尾再写，两个写入者会定位到同一处，后写的盖掉先写的）
// - 写入在私有串行队列上，调用方不阻塞；用会 throw 的 write(contentsOf:)，失败只记到 os.Logger，不崩溃
//   （旧版 FileHandle.write(_:) 遇到磁盘满会抛 ObjC 异常让进程崩溃，物理屏关着时就没人恢复了）
// - 超过上限滚动一份 .1。滚动前比对 inode：别的进程已经滚动过，就只重新打开，不再滚第二次
import Foundation
import os

public final class FileLogSink: LogSink, @unchecked Sendable {
    public static let defaultMaxBytes: UInt64 = 5 * 1024 * 1024

    private let url: URL
    private let rotatedURL: URL
    private let processTag: String?
    private let maxBytes: UInt64
    private let queue = DispatchQueue(label: "com.zephyr4123.snug.log-file")
    private let fallback = Logger(subsystem: Log.subsystem, category: "log-file")
    // 以下两项只在 queue 上访问
    private var handle: FileHandle?
    private let formatter: DateFormatter

    /// processTag：看门狗进程传「看门狗」，每行带上 [看门狗]
    public init(url: URL, processTag: String? = nil, maxBytes: UInt64 = FileLogSink.defaultMaxBytes) {
        self.url = url
        self.rotatedURL = url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + ".1")
        self.processTag = processTag
        self.maxBytes = maxBytes
        formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    }

    public func write(_ level: LogLevel, _ message: String, at date: Date) {
        queue.async { self.append(level, message, date) }
    }

    /// 等队列里已提交的行都写完（测试、进程退出前用）
    public func flush() {
        queue.sync {}
    }

    private func append(_ level: LogLevel, _ message: String, _ date: Date) {
        let tag = processTag.map { " [\($0)]" } ?? ""
        let line = "[\(formatter.string(from: date))] [\(level.rawValue)]\(tag) \(message)\n"
        do {
            let h = try currentHandle()
            try h.write(contentsOf: Data(line.utf8))
        } catch {
            fallback.error("写日志文件失败 \(self.url.path, privacy: .public)：\(String(describing: error), privacy: .public)")
            closeHandle()
        }
    }

    private func currentHandle() throws -> FileHandle {
        if let h = handle {
            if try needsRotation(h) {
                closeHandle()
                try rotateIfStillOurs()
            } else {
                return h
            }
        }
        let h = try openAppend()
        handle = h
        return h
    }

    private func openAppend() throws -> FileHandle {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fd = open(url.path, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC, 0o644)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        return FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    }

    /// 句柄指向的文件已超限，或者路径上已经换成了别的文件（另一个进程滚动过）
    private func needsRotation(_ h: FileHandle) throws -> Bool {
        var mine = stat()
        guard fstat(h.fileDescriptor, &mine) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        var onDisk = stat()
        if stat(url.path, &onDisk) != 0 || onDisk.st_ino != mine.st_ino { return true }
        return UInt64(mine.st_size) >= maxBytes
    }

    private func rotateIfStillOurs() throws {
        var onDisk = stat()
        guard stat(url.path, &onDisk) == 0, UInt64(onDisk.st_size) >= maxBytes else { return }
        // rename 会原子替换旧的 .1
        guard rename(url.path, rotatedURL.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }

    private func closeHandle() {
        guard let h = handle else { return }
        handle = nil
        do { try h.close() } catch {
            fallback.error("关闭日志文件失败：\(String(describing: error), privacy: .public)")
        }
    }
}
