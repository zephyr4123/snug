// 发布给界面的状态。界面只读它，改动一律走意图协议（由 AppController 实现）。
// 菜单栏、设置窗口、手机屏上的列表读的是同一份状态：任何入口改了，所有界面一起变
import Observation
import SnugCore

enum ConnectionPhase: Equatable {
    case idle
    case connected
    /// 断开了，还在重连窗口里（这段时间内再连上算同一次远程，手机屏留着）
    case reconnecting
}

@MainActor
@Observable
final class AppState {
    var config = AppConfig()
    var connection = ConnectionPhase.idle
    var controller: String?
    /// UU 此刻在推的屏
    var streamedDisplay: DisplayID?
    var phone = PhoneDesk.State()
    /// 手势翻译要开却没开起来（建事件监听失败）
    var gesturesFailed = false
    var accessibilityTrusted = false
    var launchAtLogin = false
    /// 上一次打开开机启动没成
    var loginItemIssue: LoginItemIssue?
    /// 上一次改设置没能写进 config.json
    var configSaveFailed = false
    /// 旧版「UU远程伴侣」正在运行
    var legacyAppRunning = false
    /// 正在退出收尾
    var quitting = false

    init() {}

    /// UU 正在推手机屏，也就是用户此刻正在手机屏上
    var phoneInUse: Bool {
        guard let display = phone.display else { return false }
        return streamedDisplay == display
    }

    /// 只在值真的变了时才写，免得每拍都让界面重算
    func update<T: Equatable>(_ keyPath: ReferenceWritableKeyPath<AppState, T>, _ value: T) {
        if self[keyPath: keyPath] != value { self[keyPath: keyPath] = value }
    }
}

enum LoginItemIssue: Equatable {
    /// 用户在「登录项」里关过 Snug，要在那里允许
    case needsApproval
    /// Snug 不在「应用程序」里
    case notInApplications
    case failed
}

/// 设置窗口、菜单栏能发起的意图。AppController 是唯一实现（渲染 PNG 时用一个什么都不做的替身）
@MainActor
protocol AppIntents: AnyObject {
    func setPhoneScreen(_ on: Bool)
    func setGestures(_ on: Bool)
    func setZoomSteps(_ steps: Int)
    func setLaunchAtLogin(_ on: Bool)
    func markWelcomed()
    func quitLegacyApp()
    func quit()
}

/// 手机屏上的列表和小横条能发起的意图
@MainActor
protocol PhoneIntents: AnyObject {
    func pull(_ window: WindowInfo)
    func showList()
    func returnToPlaced()
    func putBack()
    func zoom(by delta: Int)
}

/// 打开各个窗口
@MainActor
protocol Navigation: AnyObject {
    func openSettings()
    func openWelcome()
    func openAbout()
}
