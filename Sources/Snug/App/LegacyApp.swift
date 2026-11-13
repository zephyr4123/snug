// 旧版「UU远程伴侣」（com.corndog.uudisplay）和 Snug 同时运行会一起改屏幕、互相干扰
import AppKit
import SnugCore

@MainActor
enum LegacyApp {
    nonisolated static let bundleID = "com.corndog.uudisplay"

    static var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty }

    /// 请旧版正常退出（它会先把自己改过的屏幕还原）
    static func quit() {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        for app in apps where !app.terminate() {
            Log.warn("请旧版 UU远程伴侣（pid \(app.processIdentifier)）退出没有成功")
        }
        if !apps.isEmpty { Log.info("已请旧版 UU远程伴侣 退出") }
    }

    /// 每 0.5s 看一眼，旧版退出了或超时就回调
    static func waitUntilGone(timeout: TimeInterval, then done: @escaping @MainActor () -> Void) {
        guard isRunning, timeout > 0 else {
            if isRunning { Log.warn("旧版 UU远程伴侣 还没退出，照常开始监控") }
            return done()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            MainActor.assumeIsolated { waitUntilGone(timeout: timeout - 0.5, then: done) }
        }
    }

    /// 旧版启动、退出时回调，参数是此刻它是否在运行
    static func observe(_ onChange: @escaping @MainActor (Bool) -> Void) -> [any NSObjectProtocol] {
        let center = NSWorkspace.shared.notificationCenter
        return [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification].map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard app?.bundleIdentifier == bundleID else { return }
                MainActor.assumeIsolated { onChange(isRunning) }
            }
        }
    }
}
