// 时间来源与延时执行。执行器等逻辑只认这个协议，测试里换成虚拟时钟做离散事件仿真
import Foundation

@MainActor
public protocol Scheduler: AnyObject {
    var now: Date { get }
    func after(_ seconds: TimeInterval, _ block: @escaping @MainActor @Sendable () -> Void)
}

/// 正式运行用：主队列延时执行。now 由单调时钟推出（起点对齐启动时的墙钟），
/// 系统改时间不会让「已经等了多久」算错（PR #14 的冷却用墙钟，时间回拨会让执行器挂很久）
@MainActor
public final class MainQueueScheduler: Scheduler {
    private let anchorDate = Date()
    private let anchorUptime = ProcessInfo.processInfo.systemUptime

    public init() {}

    public var now: Date {
        anchorDate.addingTimeInterval(ProcessInfo.processInfo.systemUptime - anchorUptime)
    }

    public func after(_ seconds: TimeInterval, _ block: @escaping @MainActor @Sendable () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, seconds)) {
            MainActor.assumeIsolated { block() }
        }
    }
}
