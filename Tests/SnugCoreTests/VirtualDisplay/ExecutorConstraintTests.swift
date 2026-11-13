import Foundation
import Testing
@testable import SnugCore

/// 原作者实测出来的 7 条硬约束。假驱动的动作耗时：建屏 0.29、设主屏 0.30、关屏 0.13、恢复 0.12、释放 0.09、布局 0.08；
/// 虚拟屏建好 0.3s 后上线。断言里的时刻都写成「上一步完成时刻 + 稳定等待」
@Suite("显示执行器：硬约束")
@MainActor
struct ExecutorConstraintTests {
    @Test("约束 1：一次只做一步，每步后等待（建屏 1.0、设主屏 0.5、关屏 1.5、恢复 1.5、释放 1.5、布局 0.5）")
    func oneStepAtATime() {
        let rig = ExecutorRig()
        rig.executor.setTarget(profile: iPhone, keepOnlyVirtual: true)
        rig.run(until: 10)
        #expect(Array(rig.callNames.prefix(4)) == ["captureLayout", "create", "setMain", "disable"])
        #expect(near(rig.first("create"), 0))                    // 首连不做确认延迟
        #expect(near(rig.first("setMain"), 0.29 + 1.0))
        #expect(near(rig.first("disable"), 1.59 + 0.5))
        #expect(rig.calls("disable").first?.ids == [1, 5])
        #expect(rig.executor.physicalOff)

        rig.at(20) { rig.executor.setTarget(profile: nil, keepOnlyVirtual: false) }
        rig.run(until: 40)
        #expect(near(rig.first("enable"), 20))                    // 目标变成「无」立刻恢复物理屏
        #expect(near(rig.first("release"), 20 + 10))              // 虚拟屏保留 10s 宽限
        #expect(near(rig.first("restoreModes"), 30.09 + 1.5))
        #expect(near(rig.first("restoreOrigins"), 31.67 + 0.5))   // 模式、原点分两个事务
        #expect(rig.driver.layoutRecord == false)
        #expect(rig.driver.virtualCount == 0)
        #expect(!rig.executor.physicalOff)
        // 每做完一次拓扑事务都通知（建、设主、关、开、放、模式、原点）
        #expect(rig.topologyChanges.count == 7)
    }

    @Test("约束 2：释放前必须已上线且存活 ≥2.5s")
    func minimumLifetime() {
        let rig = ExecutorRig()
        rig.executor.setTarget(profile: iPhone, keepOnlyVirtual: false)
        rig.at(1.0) { rig.executor.shutdown {} }
        rig.run(until: 20)
        #expect(rig.first("setMain") == nil)
        #expect(near(rig.first("release"), 0.29 + 2.5))
    }

    @Test("约束 2：一直不上线的屏，从出生算最多等 8s 再强制释放；也绝不关物理屏（修 B7）")
    func maxReleaseWaitAndNoPhysicalOff() {
        let rig = ExecutorRig()
        rig.driver.onlineDelay = nil
        rig.executor.setTarget(profile: iPhone, keepOnlyVirtual: true)
        rig.run(until: 30)
        #expect(rig.driver.count("create") == 1)      // 记下失败的配置，不重试
        #expect(rig.driver.count("disable") == 0)
        #expect(rig.driver.count("setMain") == 0)
        #expect(near(rig.first("release"), 0.29 + 8))
        if case .createFailed = rig.executor.lastError {} else { Issue.record("应暴露建屏失败：\(String(describing: rig.executor.lastError))") }
    }

    @Test("约束 3：applySettings 失败的屏放进 broken，稳定后再释放，不能立即释放")
    func brokenReleasedLater() {
        let rig = ExecutorRig()
        rig.driver.applySettingsFails = true
        rig.executor.setTarget(profile: iPhone, keepOnlyVirtual: true)
        rig.run(until: 30)
        #expect(near(rig.first("release"), 0.29 + 8))
        #expect(rig.driver.count("create") == 1)
        #expect(rig.driver.count("disable") == 0)
        #expect(rig.driver.virtualCount == 0)
    }

    @Test("约束 5：事务返回 cannotComplete(1004) / 1014 进入 wedged，除了恢复物理屏停止一切拓扑变化")
    func wedged() {
        let rig = ExecutorRig()
        rig.executor.setTarget(profile: iPhone, keepOnlyVirtual: true)
        rig.run(until: 10)
        #expect(rig.executor.physicalOff)

        rig.driver.setMainError = .cgError(1014)
        rig.at(10) { rig.executor.setTarget(profile: iPad, keepOnlyVirtual: true) }
        rig.run(until: 20)
        #expect(rig.executor.wedged)
        #expect(near(rig.first("enable"), 11.59 + 0.5))   // 物理屏照样恢复
        rig.at(20) { rig.executor.setTarget(profile: nil, keepOnlyVirtual: false) }
        rig.run(until: 60)
        #expect(rig.driver.count("release") == 0)
        #expect(rig.driver.count("restoreModes") == 0)
        #expect(rig.driver.count("create") == 2)
    }

    @Test("约束 5：1004 同样进入 wedged，之后 shutdown 也能收尾回调")
    func wedgedShutdown() {
        let rig = ExecutorRig()
        rig.driver.setMainError = .cgError(1004)
        rig.executor.setTarget(profile: iPhone, keepOnlyVirtual: false)
        rig.run(until: 5)
        #expect(rig.executor.wedged)
        var done = false
        rig.executor.shutdown { done = true }
        rig.run(until: 10)
        #expect(done)
        #expect(rig.driver.count("release") == 0)
    }

    @Test("约束 6：物理屏是否被禁用以磁盘记录为准（看门狗已在别的进程恢复）")
    func diskIsTruth() {
        let rig = ExecutorRig()
        rig.executor.setTarget(profile: iPhone, keepOnlyVirtual: true)
        rig.run(until: 5)
        #expect(rig.executor.physicalOff)
        rig.driver.watchdogRestoredEverything()
        #expect(!rig.executor.physicalOff)
        rig.at(6) { rig.executor.setTarget(profile: nil, keepOnlyVirtual: false) }
        rig.run(until: 30)
        #expect(rig.driver.count("enable") == 0)
    }

    @Test("约束 7：虚拟屏建好后不改；同规格换名字直接复用，不重建")
    func neverModified() {
        let rig = ExecutorRig()
        rig.executor.setTarget(profile: iPhone, keepOnlyVirtual: false)
        rig.run(until: 5)
        let twin = DeviceProfile(name: "另一台手机", kind: .phone, width: 2400, height: 1320)
        rig.at(5) { rig.executor.setTarget(profile: twin, keepOnlyVirtual: false) }
        rig.run(until: 20)
        #expect(rig.driver.count("create") == 1)
        #expect(rig.driver.count("release") == 0)
    }
}
