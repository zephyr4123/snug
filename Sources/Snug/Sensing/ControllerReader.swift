// 后台读 UU 的「本机被控中」表格：串行，同一时刻只有一次读取在跑（不堆积），读得太慢的结果丢弃。
// 结果放在加锁的盒子里，主线程每拍直接取，不经主队列转发。旧版把结果投回主线程再按「到达时间」判新鲜，
// 主线程一卡 2 秒，后台早就读好的结果也被当成过期丢掉，没有覆盖窗口的会话就被误判断开（B4）
import Foundation
import os
import SnugCore

@MainActor
final class ControllerReader {
    /// 一次读取超过这么久就不可信（UU 卡住时 AX 每次调用最多等 1 秒，一棵树要调很多次）
    nonisolated static let maxReadDuration: TimeInterval = 2

    private struct Box: Sendable {
        var inFlightSince: TimeInterval?
        var latest: [String]?
        var generation = 0
    }

    private let queue = DispatchQueue(label: "com.zephyr4123.snug.ax-reader", qos: .utility)
    private let box = OSAllocatedUnfairLock(initialState: Box())

    /// 每拍调用：返回此刻可信的控制端（nil = 读不到），没有读取在跑就发起下一次
    func poll() -> [String]? {
        guard UUAccessibility.isTrusted, let pid = UURemoteApp.pid() else {
            reset()
            return nil
        }
        let now = Self.uptime()
        let (current, start, generation) = box.withLock { b -> ([String]?, Bool, Int) in
            if let since = b.inFlightSince {
                // 读取卡住超过上限：手上的结果已经说明不了现在
                return (now - since > Self.maxReadDuration ? nil : b.latest, false, b.generation)
            }
            b.inFlightSince = now
            return (b.latest, true, b.generation)
        }
        if start { read(pid: pid, generation: generation) }
        return current
    }

    private func read(pid: pid_t, generation: Int) {
        let box = box
        queue.async {
            let started = Self.uptime()
            let names = autoreleasepool { UUAccessibility.readControllers(pid: pid) }
            let took = Self.uptime() - started
            if took > Self.maxReadDuration {
                Log.warn(String(format: "读 UU 控制端表格用了 %.1fs，结果丢弃", took))
            }
            box.withLock { b in
                guard b.generation == generation else { return }
                b.inFlightSince = nil
                b.latest = took <= Self.maxReadDuration ? names : nil
            }
        }
    }

    /// 没授权或 UU 没在运行：清空，在途的读取结果作废
    private func reset() {
        box.withLock { b in
            b.generation += 1
            b.inFlightSince = nil
            b.latest = nil
        }
    }

    private nonisolated static func uptime() -> TimeInterval { ProcessInfo.processInfo.systemUptime }
}
