// UU远程 自身的几样直接观测：进程号、覆盖窗口在不在屏
import AppKit
import CoreGraphics

@MainActor
enum UURemoteApp {
    /// UU远程 主程序的进程号；没在运行返回 nil
    static func pid() -> pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: UUAccessibility.bundleID).first?.processIdentifier
    }

    /// UURemoteServer 的覆盖窗口在屏：被远程时 UU 会在本机屏幕上放一个提示窗口
    static func overlayVisible() -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        return list.contains { ($0[kCGWindowOwnerName as String] as? String) == "UURemoteServer" }
    }
}
