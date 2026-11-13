// 看门狗的 LaunchAgent（~/Library/LaunchAgents + launchctl，KeepAlive）：设置里打开才安装，关掉就卸载。
// 不用 SMAppService.agent：自签证书（没有 Team ID）签名时，BTM 生成的启动约束是空的 cdhash 列表，
// launchd 一直拉不起来（EX_CONFIG / OS_REASON_CODESIGNING，原作者实测）。
// launchctl 是同步子进程，安装 / 卸载放后台串行队列；退出时停看门狗要等它做完，用同步版本
import Foundation
import SnugCore

final class WatchdogAgent: Sendable {
    static let label = "com.zephyr4123.snug.watchdog"
    /// 看门狗每 5s 写一次心跳；超过两轮多没写就算没在跑
    static let heartbeatMaxAge: TimeInterval = 12

    private let executable: URL
    private let plistURL: URL
    private let bundleID: String
    private let heartbeat: URL
    private let queue = DispatchQueue(label: "com.zephyr4123.snug.launchctl", qos: .utility)

    /// 只在以 .app 运行时管理看门狗；调试运行（swift run）返回 nil
    init?(bundle: Bundle, paths: SnugPaths) {
        guard bundle.bundlePath.hasSuffix(".app") else { return nil }
        executable = bundle.bundleURL.appendingPathComponent("Contents/MacOS/SnugWatchdog")
        plistURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(Self.label).plist")
        bundleID = bundle.bundleIdentifier ?? "com.zephyr4123.snug"
        heartbeat = paths.watchdogHeartbeat
    }

    /// 心跳文件不存在（没装、或刚卸载）就是没在跑
    static func isRunning(heartbeat url: URL) -> Bool {
        var st = stat()
        guard stat(url.path, &st) == 0 else { return false }
        return Date().timeIntervalSince1970 - TimeInterval(st.st_mtimespec.tv_sec) < heartbeatMaxAge
    }

    /// 按设置安装或卸载（后台执行）
    func sync(enabled: Bool) {
        queue.async { enabled ? self.install() : self.uninstall() }
    }

    /// 停掉本次登录中的看门狗，保留 LaunchAgent（下次打开 App 或重新登录时恢复）。同步执行
    func stopForSession() {
        queue.sync {
            guard isLoaded else { return }
            let rc = launchctl(["bootout", target])
            Log.info(rc == 0 ? "已停止本次登录中的看门狗" : "停止看门狗失败（launchctl 返回 \(rc)）")
        }
    }

    // MARK: 只在 queue 上调用

    private var domain: String { "gui/\(getuid())" }
    private var target: String { "\(domain)/\(Self.label)" }
    private var isLoaded: Bool { launchctl(["print", target]) == 0 }

    private func install() {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            Log.error("找不到看门狗可执行文件，没有安装：\(executable.path)")
            return
        }
        let data: Data
        do {
            data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        } catch {
            Log.error("生成看门狗 LaunchAgent 配置失败：\(error)")
            return
        }
        let existing: Data?
        do {
            existing = try Data(contentsOf: plistURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            existing = nil
        } catch {
            Log.warn("读不出现有的看门狗配置，重写一份：\(error)")
            existing = nil
        }
        let changed = existing != data
        if changed {
            do {
                try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: plistURL, options: .atomic)
            } catch {
                Log.error("写看门狗 LaunchAgent 配置失败：\(error)")
                return
            }
            if isLoaded { launchctl(["bootout", target]) }
        }
        guard !isLoaded else { return }
        let rc = launchctl(["bootstrap", domain, plistURL.path])
        if rc == 0 {
            Log.info("看门狗已加载")
        } else {
            Log.warn("看门狗加载失败（launchctl 返回 \(rc)），可能被「登录项与扩展」里的后台开关关掉了")
        }
    }

    private func uninstall() {
        let loaded = isLoaded
        if loaded { launchctl(["bootout", target]) }
        let existed = FileManager.default.fileExists(atPath: plistURL.path)
        do {
            if existed { try FileManager.default.removeItem(at: plistURL) }
            if FileManager.default.fileExists(atPath: heartbeat.path) { try FileManager.default.removeItem(at: heartbeat) }
        } catch {
            Log.error("移除看门狗配置失败：\(error)")
        }
        if loaded || existed { Log.info("已卸载看门狗") }
    }

    private var plist: [String: Any] {
        [
            "Label": Self.label,
            "ProgramArguments": [executable.path, "--watchdog"],
            "KeepAlive": true,
            // 被结束后最快 5 秒重新拉起（launchd 默认 10 秒），也避免反复崩溃时频繁重启
            "ThrottleInterval": 5,
            "RunAtLoad": true,
            "ProcessType": "Interactive",
            "LimitLoadToSessionType": "Aqua",
            // 让「登录项与扩展」把它显示为 Snug，而不是一个陌生的可执行文件
            "AssociatedBundleIdentifiers": [bundleID],
        ]
    }

    @discardableResult
    private func launchctl(_ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
        } catch {
            Log.error("运行 launchctl \(args.first ?? "") 失败：\(error)")
            return -1
        }
        p.waitUntilExit()
        return p.terminationStatus
    }
}
