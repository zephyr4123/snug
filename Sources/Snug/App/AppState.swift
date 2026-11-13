// 发布给界面的状态。界面只读它，改动一律走 AppIntents（由 AppController 实现）。
// 菜单栏、设置窗口、权限窗口读的是同一份状态：任何入口改了设置，所有界面一起变（修 B12）
import Observation
import SnugCore

enum ConnectionPhase: Equatable {
    case idle
    case connected
    /// 断开了，还在重连窗口里（这段时间内再连上算同一次远程）
    case reconnecting
}

/// UU 正在推流的那块屏
struct StreamedDisplay: Equatable {
    let id: DisplayID
    let name: String
}

/// 可选的虚拟屏功能此刻的状态
struct VirtualDisplayStatus: Equatable {
    /// 正在用的虚拟屏规格
    var activeProfile: DeviceProfile?
    /// 物理屏熄灭着（以磁盘记录为准）
    var physicalOff = false
    /// WindowServer 显示配置无响应，除恢复物理屏外停止一切显示操作
    var wedged = false
    /// 本次远程判定「熄屏不稳定」，不再熄灭物理屏
    var breakerTripped = false
    /// 本次远程用户手动恢复过屏幕
    var suspendedByUser = false
    /// 还没解决的问题（人话）
    var issue: String?
    /// 磁盘上还有没还原的布局记录
    var layoutPending = false
}

enum DeviceImportStatus: Equatable {
    case idle
    case reading
    case finished(String)
    case failed(String)
}

@MainActor
@Observable
final class AppState {
    var config = AppConfig()
    var connection = ConnectionPhase.idle
    var controller: String?
    var streamedDisplay: StreamedDisplay?
    var display = VirtualDisplayStatus()
    /// 熄灭物理屏用的私有接口是否可用
    var physicalControlAvailable = true
    var accessibilityTrusted = false
    var watchdogRunning = false
    var launchAtLogin = false
    /// 需要告诉用户、但不影响运行的问题：设置没存上、开机启动没设成功……
    var notice: String?
    /// 旧版「UU远程伴侣」正在运行
    var legacyAppRunning = false
    var deviceImport = DeviceImportStatus.idle
    /// 正在退出收尾
    var quitting = false

    init() {}

    /// 只在值真的变了时才写，免得每拍都让界面重算
    func update<T: Equatable>(_ keyPath: ReferenceWritableKeyPath<AppState, T>, _ value: T) {
        if self[keyPath: keyPath] != value { self[keyPath: keyPath] = value }
    }
}

/// 界面能发起的全部意图。AppController 是唯一实现（渲染 PNG 时用一个什么都不做的替身）
@MainActor
protocol AppIntents: AnyObject {
    func setPaused(_ on: Bool)
    func setVirtualDisplayEnabled(_ on: Bool)
    func setKeepOnlyVirtual(_ on: Bool)
    func setWatchdogEnabled(_ on: Bool)
    func setLaunchAtLogin(_ on: Bool)
    /// 按行保存（修 B10）：这一行无效就抛 DeviceSizeIssue，其余行不受影响
    func updateDevice(_ row: DeviceProfile) throws
    /// 在后台读 UU 的「全部设备」（修 B4：不在主线程读 AX、不在主线程 sleep）
    func importDevices()
    /// 热键 / 菜单：立即恢复屏幕
    func restoreScreensNow()
    func restoreLayoutNow()
    func quitLegacyApp()
    func markTourShown()
    func quit()
}

/// 打开各个窗口
@MainActor
protocol Navigation: AnyObject {
    func openSettings(page: SettingsPage?)
    func openPermissions()
    func openTour()
    func openAbout()
}
