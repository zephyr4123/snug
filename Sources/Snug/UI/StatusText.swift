// 状态文案：一个标题 + 一个短说明。把 AppState 翻成菜单栏和设置窗口共用的状态，也给手机屏上的提示用。只用短词，书面、克制
import SnugCore

struct StatusText: Equatable {
    var headline: String
    var detail: String?

    init(headline: String, detail: String?) {
        self.headline = headline
        self.detail = detail
    }

    @MainActor
    init(_ s: AppState) {
        headline = Self.headline(s)
        detail = Self.detail(s)
    }

    @MainActor
    private static func headline(_ s: AppState) -> String {
        if s.quitting { return "正在退出" }
        if !s.accessibilityTrusted { return "需要\(PermissionName.accessibility)权限" }
        switch s.connection {
        case .idle: return "等待连接"
        case .reconnecting: return "连接中断"
        case .connected: return s.controller.map { "\($0) · 远程中" } ?? "远程中"
        }
    }

    @MainActor
    private static func detail(_ s: AppState) -> String? {
        if s.quitting { return "正在还原窗口" }
        if !s.accessibilityTrusted { return "用于移动窗口与转换手势" }
        if !s.config.phoneScreen { return "手机屏已关闭" }
        if s.connection == .idle { return nil }
        if s.gesturesFailed { return "手势转换未启用" }
        switch s.phone.screen {
        case .preparing: return "正在准备手机屏"
        case .failed: return "手机屏创建失败"
        case .ready:
            guard s.phoneInUse else { return "手机屏已就绪" }
            return s.phone.placed.map { "手机屏 · \($0.window.app)" } ?? "手机屏使用中"
        case .off:
            return ControllerKind(name: s.controller) == .computer ? "电脑控制端，不提供手机屏" : nil
        }
    }
}

extension LoginItemIssue {
    /// 设置页底部的提示：写明去哪里处理
    var text: String {
        switch self {
        case .needsApproval: "开机启动待允许 · 系统设置 › 通用 › 登录项"
        case .notInApplications: "开机启动未生效 · 需位于「应用程序」"
        case .failed: "开机启动未生效 · 请稍后重试"
        }
    }
}

extension PhoneDesk.Notice {
    /// 手机屏列表顶部的提示：出了什么事，和接下来怎么办。不出现技术词
    var text: StatusText {
        switch self {
        case .windowGone(let app): StatusText(headline: "\(app) 窗口已关闭", detail: "请另选一个窗口")
        case .windowUnresponsive(let app): StatusText(headline: "\(app) 无响应", detail: "可能正忙，请稍后再试")
        case .recordUnwritable: StatusText(headline: "无法保存原位置", detail: "为确保能放回原处，窗口未移动")
        case .screenNotReady: StatusText(headline: "手机屏未就绪", detail: "屏幕正在调整，请稍后再试")
        }
    }
}
