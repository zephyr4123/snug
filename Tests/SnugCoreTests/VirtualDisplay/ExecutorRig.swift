import Foundation
@testable import SnugCore

/// 所有用例共用的时间原点
let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

let iPhone = DeviceProfile(name: "iPhone", kind: .phone, width: 2400, height: 1320)
let iPad = DeviceProfile(name: "iPad", kind: .tablet, width: 2360, height: 1640)

/// 浮点时刻比较（虚拟时钟里的秒数是若干常数相加，误差只在最后几位）
func near(_ a: Double?, _ b: Double) -> Bool {
    guard let a else { return false }
    return abs(a - b) < 1e-6
}

/// 虚拟时钟 + 假驱动 + 真执行器
@MainActor
final class ExecutorRig {
    let scheduler = VirtualScheduler(start: t0)
    let driver: FakeDisplayDriver
    let executor: DisplayExecutor
    private(set) var topologyChanges: [Double] = []

    init() {
        driver = FakeDisplayDriver(scheduler: scheduler)
        executor = DisplayExecutor(driver: driver, scheduler: scheduler)
        executor.onTopologyChange = { [unowned self] in topologyChanges.append($0.timeIntervalSince(t0)) }
    }

    var now: Double { scheduler.now.timeIntervalSince(t0) }
    func run(until s: Double) { scheduler.run(until: t0.addingTimeInterval(s)) }
    /// 在 s 秒时做某事（先把时钟推到 s）
    func at(_ s: Double, _ body: () -> Void) {
        run(until: s)
        body()
    }

    func times(_ name: String) -> [Double] { driver.names(name).map { $0.at.timeIntervalSince(t0) } }
    func first(_ name: String) -> Double? { times(name).first }
    func calls(_ name: String) -> [FakeDisplayDriver.Call] { driver.names(name) }
    var callNames: [String] { driver.calls.map(\.name) }
}
