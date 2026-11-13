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
    /// 窗口该铺满的区域（辅助功能坐标，左上原点）：这块屏扣掉菜单栏和底部小横条
    func windowArea(_ id: DisplayID) -> CGRect?
}

/// 搬窗口、调字号。辅助功能的调用会阻塞（App 卡住时每次最多等一会儿），实现放在自己的后台队列上
public protocol WindowControl: Sendable {
    /// 有没有辅助功能权限。没有时什么窗口都看不到：「找不到窗口」不能当成「窗口已关」，还原记录要留着
    var canControl: Bool { get }
    func exists(_ window: WindowKey) async -> Bool
    func frame(of window: WindowKey) async -> CGRect?
    /// 挪到 frame 并核对，对不上就重试；返回最后的位置，窗口不在了返回 nil
    @discardableResult
    func move(_ window: WindowKey, to frame: CGRect) async -> CGRect?
    func isFullScreen(_ window: WindowKey) async -> Bool
    /// 设好后等全屏动画走完再返回
    func setFullScreen(_ window: WindowKey, _ on: Bool) async
    /// 提到最前并激活它的 App：手机上敲的字才会进这个窗口
    func focus(_ window: WindowKey) async
    /// 给窗口所在的 App 发 ⌘= / ⌘-（steps 为负就缩小）。窗口不在了就不发，返回 false
    @discardableResult
    func zoom(_ window: WindowKey, steps: Int) async -> Bool
    /// 所有普通窗口此刻的位置。加屏、撤屏前拍一张：macOS 会把上次留在这块屏上的窗口自动拉过去
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
    /// CGVirtualDisplay 返回 nil 或 apply 失败
    case createFailed(serial: UInt32)
    /// 建好了却一直不上线（备用身份也都试过）
    case neverOnline

    public var description: String {
        switch self {
        case .createFailed(let serial): "CGVirtualDisplay 建不出来（serial=\(serial)）"
        case .neverOnline: "手机屏建好了但一直不上线，备用身份也都试过了"
        }
    }
}
