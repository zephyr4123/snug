import Foundation
@testable import SnugCore

/// 虚拟时钟：离散事件仿真。after() 只登记，run(until:) 按时间顺序执行，同一时刻按登记顺序
@MainActor
final class VirtualScheduler: Scheduler {
    private(set) var now: Date
    private var queue: [(at: Date, seq: Int, block: @MainActor @Sendable () -> Void)] = []
    private var seq = 0

    init(start: Date) { now = start }

    func after(_ seconds: TimeInterval, _ block: @escaping @MainActor @Sendable () -> Void) {
        seq += 1
        queue.append((now.addingTimeInterval(max(0, seconds)), seq, block))
    }

    func run(until end: Date) {
        while let i = queue.indices.min(by: { (queue[$0].at, queue[$0].seq) < (queue[$1].at, queue[$1].seq) }),
              queue[i].at <= end {
            let event = queue.remove(at: i)
            now = event.at
            event.block()
        }
        now = max(now, end)
    }

    func run(for seconds: TimeInterval) { run(until: now.addingTimeInterval(seconds)) }
}
