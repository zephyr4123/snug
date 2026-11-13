import Foundation
import Testing
@testable import SnugCore

@Suite("看门狗判定 WatchdogJudge")
struct WatchdogJudgeTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func state(keepOnly: Bool, connected: Bool = true) -> AppStateRecord {
        AppStateRecord(pid: 4242, updatedAt: t0, connected: connected, keepOnlyVirtualActive: keepOnly)
    }

    private func observe(record: Bool = true, app: AppStateRecord?, age: TimeInterval? = 1,
                         alive: Bool = true) -> WatchdogObservation {
        WatchdogObservation(hasDisabledPhysical: record, appState: app, heartbeatAge: age, appProcessAlive: alive)
    }

    @Test("没有熄屏记录：什么都不做，主程序在不在都一样")
    func nothingToGuard() {
        var j = WatchdogJudge()
        #expect(j.evaluate(observe(record: false, app: nil), now: t0) == .idle)
        #expect(j.evaluate(observe(record: false, app: state(keepOnly: false), age: 999), now: t0) == .idle)
    }

    @Test("主程序不在（没有状态文件、进程没了或 pid 已不是 Snug）：立刻恢复")
    func appGone() {
        var j = WatchdogJudge()
        #expect(j.evaluate(observe(app: nil), now: t0) == .restore(reason: .appGone))
        #expect(j.evaluate(observe(app: state(keepOnly: true), alive: false), now: t0) == .restore(reason: .appGone))
    }

    @Test("心跳超过 10s：主程序卡死，先结束它再恢复")
    func appStuck() {
        var j = WatchdogJudge()
        #expect(WatchdogJudge.heartbeatTimeout == 10)
        #expect(j.evaluate(observe(app: state(keepOnly: true), age: 10), now: t0) == .idle)
        #expect(j.evaluate(observe(app: state(keepOnly: true), age: 10.5), now: t0)
                == .killThenRestore(pid: 4242, reason: .appStuck(seconds: 10)))
    }

    @Test("主程序健康且说「此刻要熄屏」：不插手（修 B3：不再自己看覆盖窗口，没有覆盖窗口的会话也不会被点亮）")
    func appIntendsPhysicalOff() {
        var j = WatchdogJudge()
        for s in stride(from: 0.0, through: 120, by: 5) {
            #expect(j.evaluate(observe(app: state(keepOnly: true)), now: t0.addingTimeInterval(s)) == .idle)
        }
    }

    @Test("主程序健康但已不需要熄屏，物理屏却还关着：连续超过 10s 才恢复，中途主程序又要熄屏就重新计时")
    func intentLapsed() {
        var j = WatchdogJudge()
        #expect(WatchdogJudge.intentLapseLimit == 10)
        #expect(j.evaluate(observe(app: state(keepOnly: false)), now: t0) == .idle)
        #expect(j.evaluate(observe(app: state(keepOnly: false)), now: t0.addingTimeInterval(10)) == .idle)
        #expect(j.evaluate(observe(app: state(keepOnly: true)), now: t0.addingTimeInterval(11)) == .idle)
        #expect(j.evaluate(observe(app: state(keepOnly: false)), now: t0.addingTimeInterval(15)) == .idle)
        #expect(j.evaluate(observe(app: state(keepOnly: false)), now: t0.addingTimeInterval(25)) == .idle)
        #expect(j.evaluate(observe(app: state(keepOnly: false)), now: t0.addingTimeInterval(25.5)) == .restore(reason: .intentLapsed))
    }

    @Test("理由的文字讲人话，写进日志")
    func reasonText() {
        #expect(WatchdogVerdict.Reason.appGone.description == "主程序不在")
        #expect(WatchdogVerdict.Reason.appStuck(seconds: 12).description == "主程序卡住 12 秒没有心跳")
        #expect(WatchdogVerdict.Reason.intentLapsed.description == "主程序已不需要熄屏，物理屏却还关着")
    }
}
