// 屏幕调度要用到的系统能力：建屏换档（VirtualDisplays）、搬窗口（WindowControl）、开关 App（AppControl）。
// 实现在 SnugSystem（CGVirtualDisplay、辅助功能、按键、NSWorkspace），测试里换成假的
import CoreGraphics
import Foundation

/// 建屏、撤屏、换档。CGVirtualDisplay 要在主线程建和释放
@MainActor
public protocol VirtualDisplays: AnyObject {
    /// 按身份和 fit 建一块屏（登记它的每一档），等它上线，尽量切到基准宽度（切不成只记日志、照样返回）。
    /// 上线不了就换备用身份，都不行就抛错
    func create(_ spec: ScreenSpec, _ fit: ScreenFit) async throws -> DisplayID
    /// 换比例：在线换成 fit 的档位（屏不掉线、编号不变，远控里选中的屏不丢），再切到基准宽度。换不成返回 false，屏还是原来的档位
    func reshape(_ id: DisplayID, to fit: ScreenFit) async -> Bool
    /// 这块屏登记的是哪个比例的档位（建屏或换比例时登记的）；不是这里建的返回 nil。选档只能在它的档位里选
    func fit(_ id: DisplayID) -> ScreenFit?
    /// 释放，等一会儿它下线；返回下线了没有。显示器睡着（Mac 锁屏）时释放的虚拟屏要等唤醒才下线
    func retire(_ id: DisplayID) async -> Bool
    /// 这块屏还在不在线（撤掉的屏真下线了没有）
    func isOnline(_ id: DisplayID) -> Bool
    /// 此刻是哪一档（2 倍模式的宽度，点）；不是 2 倍、或屏不在了返回 nil
    func width(_ id: DisplayID) -> Int?
    /// 换到这一档的 2 倍模式（高按这块屏现在的比例），等界面认到新尺寸再返回。换不成只记日志：窗口照样能用，只是没铺满
    func setWidth(_ id: DisplayID, _ width: Int) async
    /// 整块屏的范围（辅助功能坐标，左上原点）。撤屏前用它认出原本就在这块屏上的窗口
    func bounds(_ id: DisplayID) -> CGRect?
    /// 窗口该铺满的区域（辅助功能坐标，左上原点）：这块屏扣掉菜单栏；withHomeBar 时再扣掉底部小横条（手机、平板屏）
    func windowArea(_ id: DisplayID, withHomeBar: Bool) -> CGRect?
    /// 主屏的可放区域（辅助功能坐标）：原位落在 Snug 屏上的窗口（App 记得上次在那块屏上），原位改记成在这里居中；
    /// 撤屏前清场，屏上的窗口也挪到这里
    func mainArea() -> CGRect?
    /// 别的屏（Snug 建的屏以外的）此刻的样子。加屏、撤屏前记下：macOS 一换屏幕组合，就把别的屏拨回它给新组合记的模式
    func otherDisplays() -> [OtherDisplay]
    /// 把一块别的屏设回这个模式（交给帮手进程），permanently 时连永久配置一起写。设不成只记日志
    func setMode(_ id: DisplayID, _ mode: ScreenMode, permanently: Bool) async
}

/// 窗口此刻的样子
public struct WindowLook: Equatable, Sendable {
    /// 辅助功能坐标，左上原点。最小化的窗口是它还原后的位置
    public var frame: CGRect
    public var fullScreen: Bool
    public var minimized: Bool

    public init(frame: CGRect, fullScreen: Bool = false, minimized: Bool = false) {
        self.frame = frame
        self.fullScreen = fullScreen
        self.minimized = minimized
    }
}

/// 搬窗口、调字号。辅助功能的调用会阻塞（App 卡住时每次最多等一会儿），实现放在自己的后台队列上。
/// 除了 exists，读写窗口都经过窗口所在的 App：返回 nil / false 可能只是 App 一时没响应、或者没有辅助功能权限，
/// 窗口是不是真没了，只有 exists 说了算
public protocol WindowControl: Sendable {
    /// 窗口还在不在：问窗口服务器，不经过 App，App 卡住、没有权限都不影响
    func exists(_ window: WindowKey) async -> Bool
    /// 窗口此刻在不在屏上（也问窗口服务器）：最小化、App 被隐藏、关成了隐藏（飞书、微信点关闭只是藏起来）都不在
    func isShown(_ window: WindowKey) async -> Bool
    /// 读不到（窗口没了、App 没响应、没有权限）返回 nil
    func look(_ window: WindowKey) async -> WindowLook?
    /// 挪到 frame 并核对，对不上就重试；返回最后的位置，挪不动返回 nil
    @discardableResult
    func move(_ window: WindowKey, to frame: CGRect) async -> CGRect?
    /// 设好后等动画走完再返回
    func setFullScreen(_ window: WindowKey, _ on: Bool) async
    /// 设好后等动画走完再返回
    func setMinimized(_ window: WindowKey, _ on: Bool) async
    /// 提到最前并激活它的 App（最小化的先还原）：手机上敲的字才会进这个窗口
    func focus(_ window: WindowKey) async
    /// 给窗口所在的 App 发 ⌘= / ⌘-（steps 为负就缩小）。找不到窗口就不发，返回 false
    @discardableResult
    func zoom(_ window: WindowKey, steps: Int) async -> Bool
    /// 给窗口所在的 App 发 ⌘B 切换侧边栏。找不到窗口就不发，返回 false
    @discardableResult
    func toggleSidebar(_ window: WindowKey) async -> Bool
    /// App 此刻在屏上的标准窗口。等新窗口出现时 0.1 秒问一次，只问当前桌面空间，一次不到 1 毫秒
    func shownWindows(of pid: Int32) async -> [WindowInfo]
    /// App 在问用户的那个窗口：挂着「要存储吗」的文档窗口，或单独的对话框（多个文稿没存时的「要先检查吗」）
    func askingWindow(of pid: Int32) async -> WindowInfo?
    /// 按窗口的关闭按钮（全屏的按了没反应，要先退出全屏）。找不到窗口或按钮返回 false
    func close(_ window: WindowKey) async -> Bool
    /// 窗口关闭按钮的位置（全局坐标，左上原点）；没有关闭按钮、读不到返回 nil
    func closeButton(_ window: WindowKey) async -> CGRect?
    /// 这个进程此刻在屏上的普通窗口的位置：问窗口服务器，不经过 App，App 卡住、没有权限都不影响
    func frames(of pid: Int32) async -> [WindowKey: CGRect]
    /// 中点落在这块区域里的普通窗口（别的 App 的，不含 Snug 自己的面板）。问窗口服务器，App 卡住不影响。撤屏前清场用
    func windows(in area: CGRect) async -> [WindowKey: CGRect]
    /// 当前桌面空间里普通窗口此刻的位置。加屏、撤屏前拍一张：macOS 会把窗口挪来挪去
    func snapshot() async -> [WindowKey: CGRect]
    /// 把位置变了的窗口放回快照里的位置（except 里的除外：放在 Snug 屏上的窗口）
    func restore(_ snapshot: [WindowKey: CGRect], except: Set<WindowKey>) async
}

/// 启动、唤回、新建窗口、退出 App
public protocol AppControl: Sendable {
    /// 在跑就给进程号
    func pid(of app: AppInfo) async -> Int32?
    /// 这个 App 在跑的所有进程（一般只有一个）。认留下的账的窗口回来没有时用：App 重启后进程号会换
    func pids(bundleID: String) async -> [Int32]
    /// 没在跑就启动，在跑就「重新打开」（同点 Dock 图标，没窗口的 App 会开出窗口）。返回进程号，打不开返回 nil
    func open(_ app: AppInfo) async -> Int32?
    /// 按下菜单里的「新建窗口」（按标题认，见 NewWindowMenu；App 不在前台也行）；没有这一项、或 App 没响应返回 false
    func newWindow(pid: Int32) async -> Bool
    /// 请 App 退出（同 ⌘Q）。有未存储的内容时 App 会先问：对话框挂在文档窗口上，或单独弹一个。
    /// 交回请求有没有送到；App 已经没了也算送到（接着一看就知道它退了）
    func quit(pid: Int32) async -> Bool
    /// 强制退出，未存储的内容会丢。交回同 quit
    func forceQuit(pid: Int32) async -> Bool
    func isRunning(pid: Int32) async -> Bool
}

/// 时间：屏幕调度只认这个，测试里换成不真等的
public protocol Timeline: Sendable {
    /// 单调时间（秒）
    var now: TimeInterval { get }
    func sleep(_ seconds: TimeInterval) async
}

public struct SystemTimeline: Timeline {
    public init() {}
    public var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
    public func sleep(_ seconds: TimeInterval) async {
        try? await Task.sleep(for: .seconds(max(0, seconds)))
    }
}

public enum ScreenError: Error, CustomStringConvertible {
    /// 每个身份都建不出来（CGVirtualDisplay 返回 nil 或 apply 失败）
    case createFailed
    /// 建出来了却一直不上线（备用身份也都试过）
    case neverOnline

    public var description: String {
        switch self {
        case .createFailed: "CGVirtualDisplay 建不出来，备用身份也都试过了"
        case .neverOnline: "屏建好了但一直不上线，备用身份也都试过了"
        }
    }
}

/// 屏幕排布：设主屏、按记下的原点摆回去。主屏就是原点在 (0, 0) 的那块屏；只对本次登录生效
@MainActor
public protocol DisplayArrangement: AnyObject {
    /// 每块在线屏此刻的原点（全局坐标，左上原点）
    func origins() -> [DisplayID: CGPoint]
    /// 把这块屏设成主屏：挪到原点，别的屏跟着平移，相对位置不变
    func makeMain(_ id: DisplayID) async -> Bool
    /// 按记下的原点摆回去；记下之后才出现、或已经不在的屏不动
    func restore(_ origins: [DisplayID: CGPoint]) async -> Bool
}
