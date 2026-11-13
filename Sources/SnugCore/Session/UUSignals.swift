// 一拍里对 UU远程 的观测
import Foundation

public struct UUSignals: Equatable, Sendable, CustomStringConvertible {
    /// UURemoteServer 的覆盖窗口在屏
    public var overlayVisible: Bool
    /// UU 主窗口「本机被控中」表格里的控制端。nil = 读不到（没授权、主窗口没开、读取超时），[] = 明确无人
    public var controllers: [String]?
    /// UURemoteServer 是否在推流。nil = 未知（日志监听没在跑）
    public var captureActive: Bool?

    public init(overlayVisible: Bool, controllers: [String]?, captureActive: Bool?) {
        self.overlayVisible = overlayVisible
        self.controllers = controllers
        self.captureActive = captureActive
    }

    /// 覆盖窗口或控制端表格（推流之外的「其余信号」）
    public var uiPresent: Bool { overlayVisible || !(controllers ?? []).isEmpty }

    public var description: String {
        let names = controllers.map { $0.isEmpty ? "无" : $0.joined(separator: ",") } ?? "读不到"
        let capture = captureActive.map { $0 ? "是" : "否" } ?? "未知"
        return "overlay=\(overlayVisible ? "是" : "否") 控制端=\(names) capture=\(capture)"
    }
}

public enum ConnectionEvent: Equatable, Sendable {
    case connected(controller: String?)
    case controllerChanged(String)
    case disconnected
}
