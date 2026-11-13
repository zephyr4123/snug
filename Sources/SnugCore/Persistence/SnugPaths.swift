// 数据目录与各状态文件路径的唯一来源。测试里换成临时目录
import Foundation

public struct SnugPaths: Equatable, Sendable {
    public let dataDirectory: URL
    public let logFile: URL

    public init(dataDirectory: URL, logFile: URL) {
        self.dataDirectory = dataDirectory
        self.logFile = logFile
    }

    /// ~/Library/Application Support/Snug/ 与 ~/Library/Logs/Snug.log
    public static var standard: SnugPaths {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        return SnugPaths(
            dataDirectory: library.appendingPathComponent("Application Support/Snug", isDirectory: true),
            logFile: library.appendingPathComponent("Logs/Snug.log"))
    }

    /// 用户设置
    public var config: URL { file("config.json") }
    /// 手机屏上那个窗口的还原记录：放上去之前写，放回原位才删；崩溃后下次启动按它还原
    public var phoneRecord: URL { file("phone-screen.json") }
    /// 每个 App 在手机屏上记住的字号级数
    public var zoomBook: URL { file("zoom.json") }
    /// 日志滚动出的上一份
    public var rotatedLogFile: URL { logFile.deletingLastPathComponent().appendingPathComponent(logFile.lastPathComponent + ".1") }

    private func file(_ name: String) -> URL { dataDirectory.appendingPathComponent(name) }
}
