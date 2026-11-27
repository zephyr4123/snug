// 发布给界面的状态。界面只读它，改动一律走意图协议（由 AppController 实现）。
// 菜单栏、设置窗口、各块屏上的面板读的是同一份状态：任何入口改了，所有界面一起变
import CoreGraphics
import Observation
import SnugCore

enum ConnectionPhase: Equatable {
    case idle
    case connected
    /// 断开了，还在重连窗口里（这段时间内再连上算同一次远程，屏都留着）
    case reconnecting
}

@MainActor
@Observable
final class AppState {
    var config = AppConfig()
    /// 机型库（启动时读一次）：设置和屏上选型号用
    var devices = DeviceCatalog.empty
    var connection = ConnectionPhase.idle
    /// --preview-screens：不等远程就建屏的自测模式
    var previewing = false
    /// 此刻同时连着的控制端
    var controllers: [String] = []
    /// 登记的远控（启动时从 Remotes 取一次）：界面提到远控时按这份说，不写死哪一家
    var remotes: [RemoteIdentity] = []
    /// 这次远程归哪家远控（界面上的名字）；不在远程时为 nil
    var remoteName: String?
    /// 这次远程因为远控只在启动时认屏、又没提前准备，有开着的屏没建（ScreenPlan.withheld）：状态里提示去打开提前准备
    var screensWithheld = false
    /// 看不到某块 Snug 屏的远控（界面上的名字）：它只在启动时认屏，这块屏是它启动后才建的，要重启它
    var screensUnseenBy: String?
    /// 远控此刻在推的屏
    var streamedDisplay: DisplayID?
    /// 各块屏上的状态（DeskSet 写）
    var desks = DeskSet.State()
    /// 手势翻译要开却没开起来（建事件监听失败）
    var gesturesFailed = false
    /// 装了的、只在自己启动时认屏的远控（界面上的名字，按登记顺序）：设置里据此显示「提前准备虚拟屏」
    var launchOnlyRemotes: [String] = []
    var accessibilityTrusted = false
    /// 录屏权限：手机、平板屏上的截图要它，和辅助功能分开授权（开了截图键才去读）
    var screenRecordingTrusted = false
    var launchAtLogin = false
    /// 上一次打开开机启动没成
    var loginItemIssue: LoginItemIssue?
    /// 上一次改设置没能写进 config.json
    var configSaveFailed = false
    /// 旧版「UU远程伴侣」正在运行
    var legacyAppRunning = false
    /// 正在退出收尾
    var quitting = false
    /// 应用内更新：查到了什么、进行到哪（Updater 写）
    var update = UpdateState()
    /// 屏上浮着的截图界面：缩略图、裁剪或一句结果（Screenshots 写），和它在哪块屏上
    var screenshotOverlay: ScreenshotOverlay?
    var screenshotScreen: ScreenID?

    init() {}

    /// 配置里的这块屏
    func screen(_ id: ScreenID) -> ScreenConfig? { config.screens.first { $0.id == id } }

    /// 这块屏上的面板看到的状态
    func panel(_ id: ScreenID) -> PanelState {
        PanelState(desk: desks.desks[id] ?? Desk.State(), quitting: desks.quitting, closing: desks.closing)
    }

    /// Snug 的屏有没有人在用：远程中（含等重连），或预览自测。常驻的主屏没人远程时也在，这时面板不为它干活
    var screensInUse: Bool { connection != .idle || previewing }

    /// 这块显示器是哪块 Snug 屏；不是 Snug 的屏（内建屏、外接显示器）返回 nil
    func screenID(on display: DisplayID) -> ScreenID? {
        desks.desks.first { $0.value.display == display }?.key
    }

    /// 远控此刻在推的那块 Snug 屏，也就是用户此刻正在这块屏上
    var watchedScreen: ScreenID? { streamedDisplay.flatMap { screenID(on: $0) } }

    /// 手机（控制端）此刻在看这块屏，资源库才为它刷。不知道远控在推哪块屏（UU 是推流日志没读到）时当作在看；
    /// 没人远程时谁都没在看（常驻的主屏）
    func watching(_ id: ScreenID) -> Bool { screensInUse && (streamedDisplay == nil || watchedScreen == id) }

    /// 界面上提到远控时的名字：这次远程的那家；不在远程时是登记的全部（「UU远程、CrossDesk」），哪家都能用
    var remoteNames: String { remoteName ?? remotes.map(\.displayName).joined(separator: "、") }

    /// 连上时先推主屏的远控（界面上的名字）：设为主屏的那块，用它们时每次连接即进入
    var mainScreenRemotes: [String] { remotes.filter(\.opensOnMainScreen).map(\.displayName) }

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

/// 一块屏上的面板看到的状态：这块屏自己的，加上全局的「正在退出 / 正在关闭」
@dynamicMemberLookup
struct PanelState: Equatable {
    var desk: Desk.State
    var quitting: Set<Int32> = []
    var closing: Set<WindowKey> = []

    subscript<T>(dynamicMember keyPath: KeyPath<Desk.State, T>) -> T { desk[keyPath: keyPath] }
}

/// 设置窗口、菜单栏能发起的意图。AppController 是唯一实现（渲染 PNG 时用一个什么都不做的替身）。
/// 几个意图协议都标 Sendable：Swift 6.2 把 intents.setPhone 这种方法引用存进视图属性时要求它可跨隔离域传递
@MainActor
protocol AppIntents: AnyObject, Sendable {
    /// 屏幕列表：开关、增删、改型号、改名字（远程进行中改，只影响那一块屏，见 docs/how-it-works.md「屏幕列表」）
    func setScreenEnabled(_ id: ScreenID, _ on: Bool)
    func addScreen(orientation: Orientation, device: DeviceChoice, name: String)
    func removeScreen(_ id: ScreenID)
    /// 换型号：屏在就马上换成它的比例，分辨率回到默认
    func setScreenDevice(_ id: ScreenID, _ device: DeviceChoice)
    /// 分辨率（手机、平板）：选的基准宽度，nil 回到默认；屏在就马上换档位
    func setScreenResolution(_ id: ScreenID, _ width: Int?)
    func renameScreen(_ id: ScreenID, _ name: String)
    func setKeepScreensReady(_ on: Bool)
    /// 设为主屏的那块（常驻）；nil 不改主屏
    func setMainScreen(_ id: ScreenID?)
    func setGestures(_ on: Bool)
    func setZoomSteps(_ steps: Int)
    func setLaunchAtLogin(_ on: Bool)
    /// 开机启动待允许：直接打开系统设置的「登录项」
    func openLoginItemsSettings()
    func markWelcomed()
    func quitLegacyApp()
    /// 不等重连窗口，立即结束本次远程（断开后的重连等待期里才有意义，issue #29）
    func endSessionNow()
    func quit()
    func checkForUpdates()
    func installUpdate()
    func setUpdateSource(_ source: UpdateSource)
    /// 自动更新走不通时，打开所选更新源的下载地址
    func openDownloadPage()
    /// 指示条上的相机键（截图）
    func setScreenshot(_ on: Bool)
}

/// 一块屏上的 App 资源库和小横条能发起的意图（每块屏一份，见 ScreenIntents）
@MainActor
protocol TouchIntents: AnyObject, Sendable {
    func pull(_ window: WindowInfo)
    /// 点一个 App：在跑且有窗口就放最近用过的那个，否则打开它、等新窗口出来再放（见 AppList.action）
    func open(_ app: AppInfo)
    func newWindow(_ app: RunningApp)
    func quit(_ app: RunningApp)
    func forceQuit(pid: Int32, app: String)
    func close(_ window: WindowInfo)
    func dismissNotice()
    func showList()
    func returnToPlaced()
    func putBack()
    func zoom(by delta: Int)
    /// 换这块屏的型号
    func setDevice(_ device: DeviceChoice)
    /// 改这块屏的分辨率（nil 回到默认）
    func setResolution(_ width: Int?)
    /// 退出这块屏：这次远程不再显示（见 DeskSet.dismissScreen）
    func dismissScreen()
    /// 取消设为主屏（设为主屏的那块屏上点的）：主屏改回 Mac，这块屏不再常驻
    func cancelMain()
    /// 截铺满这块屏的窗口到剪贴板（见 Screenshots）
    func takeScreenshot()
    func openCrop()
    func cancelCrop()
    /// selection 是图片里的比例（0…1，见 CropGeometry）
    func finishCrop(_ selection: CGRect)
}

/// 打开各个窗口
@MainActor
protocol Navigation: AnyObject, Sendable {
    /// 设置、关于：从菜单栏打开时摆到点的那块屏上（display 为点的那块屏，不是从菜单栏打开的给 nil）
    func openSettings(on display: DisplayID?)
    func openWelcome()
    func openAbout(on display: DisplayID?)
    func openUpdate()
    /// 调这块屏的分辨率（屏幕详情里的「调整…」）
    func openResolution(_ id: ScreenID)
}
