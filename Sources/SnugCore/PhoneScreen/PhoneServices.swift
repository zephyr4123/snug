// PhoneDesk 要用到的系统能力。实现在 SnugSystem（CGVirtualDisplay、辅助功能、按键），测试里换成假的
import CoreGraphics
import Foundation

/// 建屏、撤屏。CGVirtualDisplay 要在主线程建和释放
@MainActor
public protocol PhoneDisplays: AnyObject {
    /// 建一块手机屏，等它上线并确保 2 倍。上线不了就换备用身份，都不行就抛错
    func create(_ spec: PhoneScreenSpec) async throws -> DisplayID
    /// 释放，等它下线
    func retire(_ id: DisplayID) async
    /// 不是 2 倍就让帮手进程切过去；返回此刻是不是 2 倍
    func ensureHiDPI(_ id: DisplayID, _ spec: PhoneScreenSpec) async -> Bool
    /// 整块屏的范围（辅助功能坐标，左上原点）。撤屏前用它认出原本就在这块屏上的窗口
    func bounds(_ id: DisplayID) -> CGRect?
    /// 窗口该铺满的区域（辅助功能坐标，左上原点）：这块屏扣掉菜单栏和底部小横条
    func windowArea(_ id: DisplayID) -> CGRect?
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
    /// 当前桌面空间里普通窗口此刻的位置。加屏、撤屏前拍一张：macOS 会把窗口挪来挪去
    func snapshot() async -> [WindowKey: CGRect]
    /// 把位置变了的窗口放回快照里的位置（except 那个除外）
    func restore(_ snapshot: [WindowKey: CGRect], except: WindowKey?) async
}

/// 时间：PhoneDesk 只认这个，测试里换成不真等的
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

public enum PhoneScreenError: Error, CustomStringConvertible {
    /// 每个身份都建不出来（CGVirtualDisplay 返回 nil 或 apply 失败）
    case createFailed
    /// 建出来了却一直不上线（备用身份也都试过）
    case neverOnline

    public var description: String {
        switch self {
        case .createFailed: "CGVirtualDisplay 建不出来，备用身份也都试过了"
        case .neverOnline: "手机屏建好了但一直不上线，备用身份也都试过了"
        }
    }
}
