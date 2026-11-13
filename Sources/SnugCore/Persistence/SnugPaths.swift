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
    /// 物理屏布局 + 显示模式快照（会话开始改拓扑前写，还原成功才删）
    public var layout: URL { file("layout.json") }
    /// 被禁用、待恢复的物理屏（先写盘再禁用）
    public var disabledDisplays: URL { file("disabled-displays.json") }
    /// 主程序每秒发布的状态，看门狗据此判断；mtime 即心跳
    public var appState: URL { file("app-state.json") }
    /// 看门狗心跳（只看 mtime）
    public var watchdogHeartbeat: URL { file("watchdog-heartbeat") }
    /// 日志滚动出的上一份
    public var rotatedLogFile: URL { logFile.deletingLastPathComponent().appendingPathComponent(logFile.lastPathComponent + ".1") }

    private func file(_ name: String) -> URL { dataDirectory.appendingPathComponent(name) }
}
