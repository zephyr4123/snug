// 一拍里对 UU远程 的观测
import Foundation

public struct UUSignals: Equatable, Sendable, CustomStringConvertible {
    /// UURemoteServer 的覆盖窗口在屏
    public var overlayVisible: Bool
    /// UU 主窗口的控制端表格
    public var controllers: ControllerTable
    /// UURemoteServer 是否在推流。nil = 未知（日志监听没在跑）
    public var captureActive: Bool?

    public init(overlayVisible: Bool, controllers: ControllerTable, captureActive: Bool?) {
        self.overlayVisible = overlayVisible
        self.controllers = controllers
        self.captureActive = captureActive
    }

    /// 任一路信号给出了在场的正面证据：覆盖窗口在屏、认出了控制端、推流在进行。
    /// 表格读不到或没认出控制端都不算缺席的证据（见 ControllerTable）
    public var isPresent: Bool { overlayVisible || !controllers.names.isEmpty || captureActive == true }

    public var description: String {
        let capture = captureActive.map { $0 ? "是" : "否" } ?? "未知"
        return "overlay=\(overlayVisible ? "是" : "否") 控制端=\(controllers) capture=\(capture)"
    }
}

public enum ConnectionEvent: Equatable, Sendable {
    case connected(controller: String?)
    case controllerChanged(String)
    case disconnected
}
