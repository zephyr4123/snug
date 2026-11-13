// 退出流程（修 B5、B6）。
// - 用户点「退出」：先在正常的 run loop 里收尾，收尾完成才停看门狗，最后才 terminate，不依赖 terminateLater
// - 系统注销、重启、关机：绝不取消（旧版一律 terminateCancel，会打断注销流程）。返回 terminateLater，
//   尽力收尾，最多等 systemQuitTimeout 就放行。会话结束时系统会丢掉本会话的显示配置，物理屏不会一直黑着；
//   超时用加进 .common 的 Timer，不靠主队列延时任务（旧版注释：terminateLater 期间它们不执行）
// - 其他来源的退出请求（AppleScript 等）：取消这一次，走用户退出的流程，收完再退
import AppKit
import SnugCore

@MainActor
final class QuitFlow {
    static let userQuitTimeout: TimeInterval = 15
    static let systemQuitTimeout: TimeInterval = 4

    private enum Phase { case running, finishing, done }

    private let controller: AppController
    private var phase = Phase.running
    private var replyPending = false
    private var poweringOffAt: Date?
    private var observer: (any NSObjectProtocol)?

    init(controller: AppController) {
        self.controller = controller
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willPowerOffNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                Log.info("系统要注销 / 重启 / 关机")
                self?.poweringOffAt = Date()
            }
        }
    }

    func userQuit() {
        guard phase == .running else { return }
        phase = .finishing
        Log.info("用户退出 Snug")
        controller.finishForQuit(stopWatchdog: true, timeout: Self.userQuitTimeout) { [weak self] in self?.finished() }
    }

    func shouldTerminate(_ app: NSApplication) -> NSApplication.TerminateReply {
        if phase == .done { return .terminateNow }
        guard isSystemQuit else {
            userQuit()
            return .terminateCancel
        }
        replyPending = true
        if phase == .running {
            phase = .finishing
            controller.finishForQuit(stopWatchdog: false, timeout: Self.systemQuitTimeout) { [weak self] in self?.finished() }
        }
        return .terminateLater
    }

    private func finished() {
        phase = .done
        Log.info("退出 Snug")
        if replyPending {
            replyPending = false
            NSApp.reply(toApplicationShouldTerminate: true)
        } else {
            NSApp.terminate(nil)
        }
    }

    /// 注销 / 重启 / 关机：看 willPowerOff 通知（一分钟内有效），或退出请求里的 kAEQuitReason
    private var isSystemQuit: Bool {
        if let at = poweringOffAt, Date().timeIntervalSince(at) < 60 { return true }
        guard let reason = NSAppleEventManager.shared().currentAppleEvent?
            .attributeDescriptor(forKeyword: AEKeyword(kAEQuitReason))?.enumCodeValue else { return false }
        let system: [OSType] = [kAELogOut, kAEReallyLogOut, kAEShowRestartDialog, kAERestart,
                                kAEShowShutdownDialog, kAEShutDown].map { OSType($0) }
        return system.contains(reason)
    }
}
