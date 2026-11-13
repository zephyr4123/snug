import Foundation
@testable import SnugCore

/// 会话层 + 虚拟屏模块的闭环：每 0.5s 一拍，把假 UU 的信号喂给 RemoteSession，再交给 VirtualDisplayFeature。
/// 接线和第二阶段 AppController 要做的一样：执行器每次改拓扑都告诉会话层（自扰静默期）
@MainActor
final class SessionRig {
    let rig = ExecutorRig()
    let feature: VirtualDisplayFeature
    var session = RemoteSession()
    var signals: () -> UUSignals = { UUSignals(overlayVisible: false, controllers: [], captureActive: nil) }
    private(set) var transitions: [(at: Double, transition: SessionTransition)] = []
    /// 熔断跳闸的时刻
    private(set) var trippedAt: Double?

    static var config: AppConfig {
        var c = AppConfig()
        c.devices = [iPhone, iPad]
        c.virtualDisplayEnabled = true
        c.keepOnlyVirtual = true
        return c
    }

    init(config: AppConfig = SessionRig.config) {
        feature = VirtualDisplayFeature(executor: rig.executor,
                                        settings: .init(config: config, physicalControlAvailable: true))
        rig.executor.onTopologyChange = { [unowned self] in session.noteSelfInducedChange(at: $0) }
    }

    var driver: FakeDisplayDriver { rig.driver }
    var now: Double { rig.now }

    func tick() {
        let tr = session.update(signals(), now: rig.scheduler.now)
        transitions += tr.map { (now, $0) }
        feature.handle(tr, session: session)
        if trippedAt == nil, feature.breaker.tripped { trippedAt = now }
    }

    /// 从 start 起每 0.5s 一拍（相位与真实日志对齐时用 start 调）
    func startTicking(at start: Double) {
        rig.scheduler.after(start - now) { [unowned self] in loop() }
    }

    private func loop() {
        tick()
        rig.scheduler.after(0.5) { [unowned self] in loop() }
    }

    func run(until s: Double) { rig.run(until: s) }

    /// 热键 / 菜单：先在会话层登记手动叫停，再让模块恢复（和 AppController 的接线一致）
    @discardableResult
    func pressRestoreHotkey() -> Bool {
        let inSession = session.suspendByUser()
        feature.userRequestedRestore(session: session)
        return inSession
    }

    func times(_ t: SessionTransition) -> [Double] { transitions.filter { $0.transition == t }.map(\.at) }
}

/// 假 UU：只有控制端表格这一路信号（19:01 那次覆盖窗口缺席）。它对假驱动的物理屏状态做出反应：
/// 关屏后按 lossOffsets 依次在若干秒后消失（届时物理屏仍关着才算），恢复物理屏后 0.02s 回来
@MainActor
final class FakeUU {
    private(set) var on = false
    private var ended = false
    private var lossOffsets: [Double]
    private let scheduler: VirtualScheduler
    private(set) var log: [(at: Double, on: Bool)] = []

    init(rig: SessionRig, lossOffsets: [Double]) {
        self.lossOffsets = lossOffsets
        scheduler = rig.rig.scheduler
        rig.signals = { [unowned self] in
            UUSignals(overlayVisible: false, controllers: on ? ["iPhone"] : [], captureActive: nil)
        }
        let driver = rig.driver
        driver.onPhysicalChange = { [unowned self, unowned driver] off in
            if off {
                // 信号已经没了的那次关屏（例如 19:01 第一轮）不消耗偏移量
                guard on, !self.lossOffsets.isEmpty else { return }
                let offset = self.lossOffsets.removeFirst()
                scheduler.after(offset) { [unowned self] in
                    if !driver.ledger.isEmpty { set(false) }
                }
            } else {
                scheduler.after(0.02) { [unowned self] in if !ended { set(true) } }
            }
        }
    }

    func at(_ s: Double, _ value: Bool, end: Bool = false) {
        scheduler.after(s - scheduler.now.timeIntervalSince(t0)) { [unowned self] in
            if end { ended = true }
            set(value)
        }
    }

    private func set(_ value: Bool) {
        guard on != value else { return }
        on = value
        log.append((scheduler.now.timeIntervalSince(t0), value))
    }
}
