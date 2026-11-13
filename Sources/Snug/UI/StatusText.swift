// 状态文案：把 AppState 翻成一句标题 + 几行说明，菜单栏和设置窗口共用。讲人话，不讲内部术语
import SnugCore

struct StatusText: Equatable {
    var headline: String
    var details: [String]

    @MainActor
    init(_ s: AppState) {
        headline = Self.headline(s)
        details = Self.details(s)
    }

    @MainActor
    private static func headline(_ s: AppState) -> String {
        if s.quitting { return "正在退出，先把屏幕还原" }
        if s.display.wedged { return "屏幕设置没有响应，请注销或重启 Mac" }
        switch s.connection {
        case .idle: return s.config.paused ? "已暂停，等待 UU远程 连接" : "等待 UU远程 连接"
        case .reconnecting: return "连接断了，等它重连"
        case .connected: return s.controller.map { "「\($0)」正在远程这台 Mac" } ?? "有设备正在远程这台 Mac"
        }
    }

    @MainActor
    private static func details(_ s: AppState) -> [String] {
        var lines: [String] = []
        if let d = s.streamedDisplay { lines.append("UU远程 在推送：\(d.name)") }
        if s.connection == .connected, s.config.paused { lines.append("已暂停，不做任何调整") }
        if let v = virtualDisplayLine(s) { lines.append(v) }
        if s.display.breakerTripped { lines.append("熄屏后连接不稳，这次远程不再熄灭屏幕") }
        if s.display.suspendedByUser { lines.append("这次远程已手动恢复屏幕") }
        if let issue = s.display.issue, !s.display.wedged { lines.append(issue) }
        return lines
    }

    @MainActor
    private static func virtualDisplayLine(_ s: AppState) -> String? {
        let config = s.config
        if let p = s.display.activeProfile {
            return "虚拟屏 \(p.sizeLabel)" + (s.display.physicalOff ? "，其他屏幕已熄灭" : "")
        }
        if s.display.physicalOff { return "有屏幕还熄灭着，正在恢复" }
        guard s.connection == .connected, config.virtualDisplayEnabled, !config.paused else { return nil }
        guard let name = s.controller else { return "还没认出是哪台设备，暂不准备虚拟屏" }
        guard let device = config.device(named: name) else { return "「\(name)」不在设备表里，不准备虚拟屏" }
        if device.kind == .computer { return "「\(name)」设成了不指定分辨率，不准备虚拟屏" }
        if !device.hasSize { return "「\(name)」还没填分辨率，不准备虚拟屏" }
        return "正在准备虚拟屏"
    }
}
