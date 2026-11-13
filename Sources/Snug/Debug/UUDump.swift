// --dump-uu：打印从 UU远程 读到的设备、控制端和覆盖窗口状态。只读 UU 的界面，不碰显示器
// （主窗口没开时会点一次 UU 的「显示主界面」）
import Foundation
import SnugCore

@MainActor
enum UUDump {
    static func run() -> Int32 {
        print("覆盖窗口：\(UURemoteApp.overlayVisible() ? "在屏" : "没有")")
        guard UUAccessibility.isTrusted else {
            print("没有辅助功能权限，读不到 UU远程 的界面")
            return 1
        }
        guard let pid = UURemoteApp.pid() else {
            print("UU远程 没有在运行")
            return 1
        }
        if !UUAccessibility.hasMainWindow(pid: pid) {
            UUAccessibility.showMainWindow(pid: pid)
            Thread.sleep(forTimeInterval: 1)
        }
        guard let devices = UUAccessibility.readDevices(pid: pid) else {
            print("读不到 UU远程 的主窗口")
            return 1
        }
        for d in devices {
            let kind = DeviceKind.guess(name: d.name, isComputerGroup: d.isComputerGroup)
            print("\(d.isSelf ? "（本机，排除）" : "")\(d.name)\t\(d.platform)\t→ \(kind.label)")
        }
        let controllers = UUAccessibility.readControllers(pid: pid)
        print("控制端：\(controllers.map { $0.isEmpty ? "无" : $0.joined(separator: "、") } ?? "读不到")")
        return 0
    }
}
