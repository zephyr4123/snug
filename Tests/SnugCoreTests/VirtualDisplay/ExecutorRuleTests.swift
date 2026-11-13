import Foundation
import Testing
@testable import SnugCore

/// 这次重构新增的规则（修 B2、B7、B8、B9、B11 及断开宽限）
@Suite("显示执行器：新增规则")
@MainActor
struct ExecutorRuleTests {
    /// 先建好屏、关掉物理屏 [1, 5]（2.22 时完成，3.72 空闲）
    private func rigWithPhysicalOff() -> ExecutorRig {
        let rig = ExecutorRig()
        rig.executor.setTarget(profile: iPhone, keepOnlyVirtual: true)
        rig.run(until: 5)
        return rig
    }

    @Test("恢复失败按 ID 分开重试，指数退避 1.5→3→6→12→30，之后每 30s；不阻塞释放虚拟屏；连续失败 8 次丢弃")
    func restoreBackoff() throws {
        let rig = rigWithPhysicalOff()
        rig.driver.enableFails = [5]
        rig.at(10) { rig.executor.setTarget(profile: nil, keepOnlyVirtual: false) }
        rig.run(until: 15)
        if case .physicalRestoreFailing = rig.executor.lastError {} else { Issue.record("应暴露恢复失败：\(String(describing: rig.executor.lastError))") }
        rig.run(until: 400)

        let enables = rig.calls("enable")
        #expect(enables.first?.ids == [1, 5])                        // 第一次一起恢复
        #expect(enables.contains { $0.ids == [1] })                  // 失败后按 ID 分开，好的那块先回来
        let attempts5 = enables.filter { $0.ids.contains(5) }.map { $0.at.timeIntervalSince(t0) }
        try #require(attempts5.count == 8)
        // 第 k 次失败（完成于 尝试时刻 + 0.12）之后至少等 backoff[k]；
        // 中间可能插进别的一步（例如先恢复好的那块、释放虚拟屏）及其稳定等待，所以上限放宽 3.5s
        let backoff: [Double] = [1.5, 3, 6, 12, 30, 30, 30]
        for k in 0..<backoff.count {
            let gap = attempts5[k + 1] - (attempts5[k] + 0.12)
            #expect(gap >= backoff[k] - 1e-6 && gap <= backoff[k] + 3.5, "第 \(k + 1) 次失败后间隔 \(gap)")
        }
        #expect(near(rig.first("release"), 10 + 10))                 // 恢复一直失败，也照常在宽限后释放
        #expect(rig.calls("forget").map(\.ids) == [[5]])             // 第 8 次失败后丢弃
        #expect(rig.driver.ledger.isEmpty)
        #expect(rig.driver.count("restoreOrigins") == 1)
    }

    @Test("热键 / 菜单恢复：立即恢复并重置退避；目标不变时不再关回去，目标换了才按新目标来")
    func manualRestore() {
        let rig = rigWithPhysicalOff()
        rig.at(5) { rig.executor.restorePhysicalNow() }
        rig.run(until: 20)
        #expect(near(rig.first("enable"), 5))
        #expect(rig.driver.count("disable") == 1)
        rig.at(20) { rig.executor.setTarget(profile: nil, keepOnlyVirtual: false) }
        rig.at(40) { rig.executor.setTarget(profile: iPhone, keepOnlyVirtual: true) }
        rig.run(until: 60)
        #expect(rig.driver.count("disable") == 2)
    }

    @Test("断开宽限：10s 内同规格的目标回来直接复用，不释放不重建")
    func graceReuse() {
        let rig = rigWithPhysicalOff()
        rig.at(10) { rig.executor.setTarget(profile: nil, keepOnlyVirtual: false) }
        rig.at(18) { rig.executor.setTarget(profile: iPhone, keepOnlyVirtual: true) }
        rig.run(until: 40)
        #expect(rig.driver.count("create") == 1)
        #expect(rig.driver.count("release") == 0)
        #expect(near(rig.first("enable"), 10))
        #expect(rig.driver.count("disable") == 2)                    // 回来后按目标再关一次
    }

    @Test("换设备 A→B：先建新屏，新屏成为主屏后再释放旧屏；布局只在第一次建屏前采集")
    func switchDevice() throws {
        let rig = rigWithPhysicalOff()
        rig.at(10) { rig.executor.setTarget(profile: iPad, keepOnlyVirtual: true) }
        rig.run(until: 30)
        #expect(rig.driver.count("captureLayout") == 1)
        let creates = rig.times("create"), mains = rig.times("setMain"), releases = rig.calls("release")
        #expect(near(creates.last, 10))
        #expect(near(mains.last, 10.29 + 1.0))
        try #require(releases.count == 1)
        #expect(releases[0].ids == [13])                             // 旧屏 #13
        #expect(near(releases.first.map { $0.at.timeIntervalSince(t0) }, 11.59 + 0.5))
        #expect(rig.executor.currentProfile == iPad)
        #expect(rig.driver.count("enable") == 0)                     // 换屏期间旧屏一直在，物理屏不用亮
    }

    @Test("A→B→A 快速切换：A 还在 retiring 里就直接复用，不撞号、不重建")
    func quickSwitchBack() {
        let rig = rigWithPhysicalOff()
        rig.at(10) { rig.executor.setTarget(profile: iPad, keepOnlyVirtual: true) }
        rig.at(10.5) { rig.executor.setTarget(profile: iPhone, keepOnlyVirtual: true) }
        rig.run(until: 40)
        #expect(rig.driver.count("create") == 2)                     // iPhone、iPad 各一次，没有第三次
        #expect(rig.calls("release").map(\.ids) == [[14]])           // 放掉的是 iPad
        #expect(rig.executor.currentProfile == iPhone)
        #expect(rig.calls("setMain").last?.ids == [13])
    }

    @Test("稳定序列号：同身份的旧屏释放后还在线时，等它下线再建，不退回随机号")
    func waitForSameIdentityOffline() throws {
        let rig = rigWithPhysicalOff()
        rig.driver.lingerAfterRelease = 2.0
        rig.at(10) { rig.executor.setTarget(profile: iPad, keepOnlyVirtual: true) }
        rig.run(until: 13)                                           // iPhone #13 在 12.09 释放，12.18 完成，在线列表里留到 14.18
        rig.executor.setTarget(profile: iPhone, keepOnlyVirtual: true)
        rig.run(until: 40)
        let creates = rig.times("create")
        try #require(creates.count == 3)
        #expect(creates[2] >= 14.18 - 1e-6)
        #expect(rig.executor.lastError == nil)
        #expect(rig.executor.currentProfile == iPhone)
    }

    @Test("布局还原失败：记录保留，有界重试 3 次后放弃；菜单「还原布局」再试，成功才删记录")
    func layoutRestoreRetries() {
        let rig = rigWithPhysicalOff()
        rig.driver.restoreOriginsFailuresLeft = 3
        rig.at(10) { rig.executor.setTarget(profile: nil, keepOnlyVirtual: false) }
        rig.run(until: 60)
        #expect(rig.driver.count("restoreOrigins") == 3)
        #expect(rig.driver.count("restoreModes") == 3)               // 每次重试都是「先模式、再原点」
        #expect(rig.driver.layoutRecord)                              // 记录还在
        if case .layoutRestoreFailed = rig.executor.lastError {} else { Issue.record("应暴露布局还原失败") }

        rig.executor.restoreLayoutNow()
        rig.run(until: 80)
        #expect(rig.driver.count("restoreOrigins") == 4)
        #expect(!rig.driver.layoutRecord)
        #expect(rig.executor.lastError == nil)
    }

    @Test("布局快照写不进磁盘：放弃本次建屏（先记账失败就不改动）")
    func layoutSnapshotFailure() {
        let rig = ExecutorRig()
        rig.driver.captureLayoutError = CocoaError(.fileWriteNoPermission)
        rig.executor.setTarget(profile: iPhone, keepOnlyVirtual: true)
        rig.run(until: 10)
        #expect(rig.driver.count("create") == 0)
        #expect(rig.driver.count("disable") == 0)
        if case .layoutSnapshotFailed = rig.executor.lastError {} else { Issue.record("应暴露快照失败") }
    }

    @Test("上线过的虚拟屏短暂离线：不按建屏失败处理；离线期间没有可用虚拟屏，物理屏恢复；回来后按目标再熄灭")
    func onlineThenOffline() {
        let rig = rigWithPhysicalOff()
        rig.driver.forcedOffline = [13]
        rig.at(5) { rig.executor.restoreLayoutNow() }   // 执行器空闲时不轮询，借一次公开调用让它看一眼
        rig.run(until: 20)
        #expect(rig.driver.count("release") == 0)
        #expect(rig.executor.lastError == nil)
        #expect(near(rig.first("enable"), 5))
        rig.driver.forcedOffline = []
        rig.run(until: 30)
        #expect(rig.driver.count("disable") == 2)
        #expect(rig.driver.count("create") == 1)
    }

    @Test("关物理屏失败：本目标内不再反复尝试")
    func disableFailureNotRetried() {
        let rig = ExecutorRig()
        rig.driver.disableError = .cgError(1000)
        rig.executor.setTarget(profile: iPhone, keepOnlyVirtual: true)
        rig.run(until: 30)
        #expect(rig.driver.count("disable") == 1)
        #expect(rig.driver.ledger.isEmpty)
    }

    @Test("空闲时外接屏插进来：执行器自己不会发现，App 层收到显示器变化后 refresh() 才按目标熄灭它")
    func refreshAfterHotplug() {
        let rig = rigWithPhysicalOff()
        rig.driver.physical.append(7)
        rig.run(until: 20)
        #expect(rig.calls("disable").map(\.ids) == [[1, 5]])
        rig.at(20) { rig.executor.refresh() }
        rig.run(until: 25)
        #expect(rig.calls("disable").map(\.ids) == [[1, 5], [7]])
        #expect(near(rig.times("disable").last, 20))
    }

    @Test("shutdown：恢复物理屏、跳过宽限释放虚拟屏、还原布局，然后回调")
    func shutdown() {
        let rig = rigWithPhysicalOff()
        var doneAt: Double?
        rig.at(5) { rig.executor.shutdown { doneAt = rig.now } }
        rig.run(until: 30)
        #expect(near(rig.first("enable"), 5))
        #expect(near(rig.first("release"), 5.12 + 1.5))
        #expect(!rig.driver.layoutRecord)
        #expect(near(doneAt, 8.79 + 0.08 + 0.5))                    // 释放 6.62→6.71，模式 8.21→8.29，原点 8.79→8.87，再等 0.5
    }
}
