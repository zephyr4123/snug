// UU远程 的身份与控制端行的识别。系统读取留在 App 层，这里只解释读到的文本。
import Foundation

public enum UURemote {
    /// UU远程 主程序
    public static let bundleID = "com.netease.uuremote"
    /// 被远程时在本机注入鼠标键盘、推流、放覆盖窗口的进程
    public static let serverProcess = "UURemoteServer"

    /// 从辅助功能表格行中提取控制端名称；没有可识别的行或名称时为未知。
    /// 主窗口可读不代表「本机被控中」列表可读，不能把首页、错误页或未暴露的行当作明确无人。
    public static func controllers(in rows: [[String]]) -> [String]? {
        var names: [String] = []
        for texts in rows where texts.contains("远程控制") {
            if let name = texts.first(where: { $0 != "远程控制" && !$0.hasPrefix("连接时长") && !$0.isEmpty }),
               !names.contains(name) {
                names.append(name)
            }
        }
        return names.isEmpty ? nil : names
    }
}
