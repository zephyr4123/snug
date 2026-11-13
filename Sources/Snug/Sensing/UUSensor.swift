// 每拍合成一份对 UU远程 的观测：覆盖窗口（同步查）、控制端表格（后台读）、推流（日志子进程）
import Foundation
import SnugCore

/// 一拍的观测
struct UUSample: Equatable {
    var signals: UUSignals
    /// UU 此刻在推的屏（推流日志里解析出来的）；不知道就是 nil
    var streamingDisplay: DisplayID?
}

@MainActor
final class UUSensor {
    private let controllers = ControllerReader()
    private let captureLog = CaptureLogWatcher()

    func start() { captureLog.start() }
    func stop() { captureLog.stop() }

    /// now 是墙钟：推流日志的时间戳是墙钟
    func sample(now: Date) -> UUSample {
        let capture = captureLog.sample(at: now)
        return UUSample(signals: UUSignals(overlayVisible: UURemoteApp.overlayVisible(),
                                           controllers: controllers.poll(),
                                           captureActive: capture.active),
                        streamingDisplay: capture.display)
    }
}
