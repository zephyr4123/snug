// config.json 的读写，只归 AppController 使用（全仓唯一写配置的地方）。
// 读：文件损坏时改名隔离再用默认值（修 B13：旧版解码失败静默换默认值，下一次写盘就把原文件覆盖了）。
// 写：改副本，写盘成功才生效；写不进去就抛错，内存里保持原样，界面不会显示一个其实没存上的值
import Foundation
import SnugCore

@MainActor
final class ConfigStore {
    private let file: JSONFile<AppConfig>?
    private(set) var config: AppConfig

    /// url 为 nil：只在内存里（--simulate / --stress 不落盘）
    init(url: URL?, initial: AppConfig? = nil) {
        file = url.map { JSONFile(url: $0) }
        config = initial ?? file?.loadOrQuarantine() ?? AppConfig()
    }

    func update(_ change: (inout AppConfig) throws -> Void) throws {
        var next = config
        try change(&next)
        guard next != config else { return }
        try file?.save(next)
        config = next
    }
}
