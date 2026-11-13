// 显示执行器（取代 DisplayManager）：调用方只声明目标，执行器一次只做一步拓扑变化，每步后等系统稳定再算下一步。
// 决策在 DisplayPlanner（纯函数），副作用在 DisplayDriver，时间在 Scheduler；这里只负责「观测 → 决策 → 执行 → 记账 → 等待」的循环。
// 限定在主线程：状态只在这里改，driver 的回调都回到主线程
import Foundation

@MainActor
public final class DisplayExecutor {
    /// 每做完一次拓扑事务就通知（接给会话层的自扰静默期）
    public var onTopologyChange: ((Date) -> Void)?
    public var onStateChange: (() -> Void)?

    private let driver: any DisplayDriver
    private let scheduler: any Scheduler
    private var state = DisplayPlanState()
    /// 动作进行中或动作后的稳定等待中：这段时间不做任何别的拓扑变化
    private var busy = false
    private var wakeToken = 0
    private var shutdownCompletion: (@MainActor @Sendable () -> Void)?

    public init(driver: any DisplayDriver, scheduler: any Scheduler) {
        self.driver = driver
        self.scheduler = scheduler
    }

    // MARK: 只读状态

    public var isActive: Bool { state.current != nil }
    public var currentProfile: DeviceProfile? { state.current?.profile }
    /// 以磁盘记录为准（看门狗等别的进程可能已经恢复）
    public var physicalOff: Bool { !driver.disabledPhysicalDisplays().isEmpty }
    public var wedged: Bool { state.wedged }
    public var lastError: DisplayIssue? { state.lastError }
    public var target: DisplayTarget { state.target }

    // MARK: 意图

    public func setTarget(profile: DeviceProfile?, keepOnlyVirtual: Bool) {
        let new = DisplayTarget(profile: profile, keepOnlyVirtual: keepOnlyVirtual)
        guard new != state.target else { return }
        Log.info("显示目标：\(state.target) → \(new)")
        state.setTarget(new, now: scheduler.now)
        kick()
    }

    /// 热键 / 菜单：立刻恢复物理屏，目标变化前不再关回去
    public func restorePhysicalNow() {
        Log.info("手动恢复物理屏")
        state.requestManualRestore(now: scheduler.now)
        kick()
    }

    /// 菜单「还原布局」：清掉放弃标记，下次拆屏后（或此刻已拆完就马上）再试
    public func restoreLayoutNow() {
        state.retryLayout()
        kick()
    }

    /// 显示器热插拔等外部变化后重新评估一次。执行器空闲时不轮询，外接屏插进来不会自己发现
    public func refresh() {
        kick()
    }

    /// 退出前收尾：恢复物理屏、跳过宽限释放虚拟屏、还原布局，然后回调
    public func shutdown(completion: @escaping @MainActor @Sendable () -> Void) {
        shutdownCompletion = completion
        state.shuttingDown = true
        kick()
    }

    // MARK: 循环

    private func kick() {
        guard !busy else { return }
        step()
    }

    private func step() {
        guard !busy else { return }
        let observation = DisplayObservation(now: scheduler.now, online: driver.onlineDisplays(),
                                             disabledPhysical: driver.disabledPhysicalDisplays(),
                                             hasLayoutSnapshot: driver.hasLayoutSnapshot())
        switch DisplayPlanner.next(state, observation) {
        case .idle:
            onStateChange?()
        case .wait(let seconds):
            wakeToken += 1
            let token = wakeToken
            scheduler.after(seconds) { [weak self] in
                guard let self, token == self.wakeToken else { return }
                self.kick()
            }
        case .act(let action):
            busy = true
            wakeToken += 1
            Log.info("执行 \(action)（目标 \(state.target)，在线 \(observation.online.map { "#\($0.id)\($0.isSnugVirtual ? "v" : "")" })）")
            perform(action)
        }
    }

    private func perform(_ action: DisplayAction) {
        switch action {
        case .restorePhysical(let ids):
            driver.enablePhysical(ids) { [weak self] result in
                guard let self else { return }
                if let f = result.failure { Log.warn("恢复物理屏 \(result.failed) 失败（\(f)），按退避重试") }
                if !result.restored.isEmpty { Log.info("✅ 已恢复物理屏 \(result.restored)") }
                state.recordRestore(result, now: scheduler.now)
                finish(topology: true, settle: DisplayTiming.settleAfterPhysical)
            }
        case .dropPhysical(let ids):
            do {
                try driver.forgetDisabled(ids)
                Log.warn("物理屏 \(ids) 连续 \(DisplayTiming.maxRestoreFailures) 次恢复失败，多半已被拔掉，从记录里移除")
                state.recordDropped(ids)
            } catch {
                Log.error("从物理屏记录里移除 \(ids) 失败：\(error)")
                state.recordDropFailed(ids, now: scheduler.now)
            }
            finish(topology: false, settle: 0)
        case .releaseBroken(let ids), .releaseVirtual(let ids):
            driver.releaseVirtual(ids) { [weak self] in
                guard let self else { return }
                Log.info("✅ 已释放虚拟屏 \(ids)")
                state.recordReleased(ids, now: scheduler.now)
                finish(topology: true, settle: DisplayTiming.settleAfterRelease)
            }
        case .abandonVirtual(let id):
            Log.warn("虚拟屏 #\(id) \(Int(DisplayTiming.onlineTimeout)) 秒内没上线，按建屏失败处理，不熄灭物理屏")
            state.recordAbandoned(id)
            finish(topology: false, settle: 0)
        case .reviveRetiring(let id):
            Log.info("复用还没释放的虚拟屏 #\(id)")
            state.recordRevived(id)
            finish(topology: false, settle: 0)
        case .captureLayout(let profile):
            do {
                try driver.captureLayout()
            } catch {
                Log.error("记录屏幕布局失败，放弃本次建屏：\(error)")
                state.recordSnapshotFailed(profile, "\(error)")
            }
            finish(topology: false, settle: 0)
        case .createVirtual(let request):
            driver.createVirtual(request) { [weak self] result in
                guard let self else { return }
                switch result {
                case .created(let id): Log.info("✅ 已创建虚拟屏 #\(id) \(request.name) \(request.profile.sizeLabel) serial=\(request.serial)")
                case .applyFailed(let id): Log.error("虚拟屏 #\(id) applySettings 失败，稳定后释放")
                case .failed(let why): Log.error("创建虚拟屏失败：\(why)")
                }
                state.recordCreated(result, request, now: scheduler.now)
                finish(topology: true, settle: DisplayTiming.settleAfterCreate)
            }
        case .setMain(let id):
            driver.setMain(id) { [weak self] outcome in
                guard let self else { return }
                log(outcome, ok: "虚拟屏 #\(id) 已设为主屏", failed: "设主屏")
                state.recordSetMain(id, outcome)
                finish(topology: true, settle: DisplayTiming.settleAfterSetMain)
            }
        case .disablePhysical(let ids):
            driver.disablePhysical(ids) { [weak self] outcome in
                guard let self else { return }
                log(outcome, ok: "已熄灭物理屏 \(ids)", failed: "熄灭物理屏")
                state.recordDisable(outcome)
                finish(topology: true, settle: DisplayTiming.settleAfterPhysical)
            }
        case .restoreModes:
            driver.restoreModes { [weak self] outcome in
                guard let self else { return }
                log(outcome, ok: "已还原显示模式", failed: "还原显示模式（继续还原原点）")
                state.recordModes(outcome)
                finish(topology: true, settle: DisplayTiming.settleAfterLayout)
            }
        case .restoreOrigins:
            driver.restoreOrigins { [weak self] outcome in
                guard let self else { return }
                log(outcome, ok: "已还原屏幕布局", failed: "还原屏幕布局（记录保留）")
                state.recordOrigins(outcome, now: scheduler.now)
                finish(topology: true, settle: DisplayTiming.settleAfterLayout)
            }
        case .finishShutdown:
            state.shutdownFinished = true
            busy = false
            Log.info("显示收尾完成")
            let done = shutdownCompletion
            shutdownCompletion = nil
            onStateChange?()
            done?()
        }
    }

    private func log(_ outcome: TransactionOutcome, ok: String, failed: String) {
        switch outcome {
        case .success: Log.info("✅ \(ok)")
        case .failure(let f) where f.isWedge: Log.error("⛔️ \(failed)：\(f)，WindowServer 显示配置无响应，停止一切显示操作（物理屏恢复除外）")
        case .failure(let f): Log.warn("\(failed)失败：\(f)")
        }
    }

    /// 动作做完：通知、记账已在调用处完成，等稳定后再算下一步
    private func finish(topology: Bool, settle: TimeInterval) {
        if topology { onTopologyChange?(scheduler.now) }
        onStateChange?()
        scheduler.after(settle) { [weak self] in
            guard let self else { return }
            busy = false
            step()
        }
    }
}
