import Foundation
import Testing
@testable import SnugCore

/// 闭环回放 2026-11-12 两次真实振荡的形态。时间轴以那一分钟的 0 秒为原点，数字和 UUDisplay.log / 系统日志直接对得上。
/// 旧版在这两段里分别把物理屏关了 4 次和 4 次（每次都是一次完整的 WindowServer 重配置，远端和本地一起闪）。
/// 新版要求：熔断后「关物理屏」最多再发生 1 次，虚拟屏从不重建，会话结束后一切还原
@Suite("虚拟屏功能模块：闭环回放")
@MainActor
struct ClosedLoopReplayTests {
    private func assertSettled(_ s: SessionRig, _ uu: FakeUU) {
        #expect(s.driver.count("create") == 1, "虚拟屏不应重建")
        guard let trip = s.trippedAt else {
            Issue.record("熔断应当跳闸")
            return
        }
        let offsAfterTrip = s.driver.names("disable").filter { $0.at.timeIntervalSince(t0) > trip }.count
        #expect(offsAfterTrip <= 1, "熔断后又关了 \(offsAfterTrip) 次物理屏")
        #expect(s.driver.ledger.isEmpty)
        #expect(s.driver.virtualCount == 0)
        #expect(!s.driver.layoutRecord)
        #expect(!s.feature.breaker.tripped, "会话结束后熔断复位")
    }

    @Test("19:01：信号在关屏后 1.22s / 5.18s 消失，首段在设主屏前就消失（21.144 出现、22.007 消失），43.417 会话结束")
    func replay1901() {
        let s = SessionRig()
        let uu = FakeUU(rig: s, lossOffsets: [1.218, 5.182])
        uu.at(21.144, true)
        uu.at(22.007, false)
        uu.at(43.417, false, end: true)
        s.startTicking(at: 20.226)          // 采样相位与旧日志一致（21.226 判连入）
        s.run(until: 120)

        #expect(s.driver.count("disable") == 1)
        #expect(s.times(.interrupted).count == 2)   // 一次是关屏扰动造成的误判（静默期过后才判），一次是真结束
        assertSettled(s, uu)
    }

    @Test("20:01：信号在关屏后 11.9s / 2.7s / 10.2s / 4.7s 消失，56.206 会话结束")
    func replay2001() {
        let s = SessionRig()
        let uu = FakeUU(rig: s, lossOffsets: [11.9, 2.7, 10.2, 4.7])
        uu.at(20.983, true)
        uu.at(56.206, false, end: true)
        s.startTicking(at: 20.724)          // 21.224 判连入，与旧日志一致
        s.run(until: 120)

        #expect(s.driver.count("disable") == 1)
        assertSettled(s, uu)
    }

    @Test("对照：熔断只在「断开时物理屏关着」才跳闸；只开虚拟屏不熄屏时，重连不影响任何东西")
    func noBreakerWithoutPhysicalOff() {
        var config = SessionRig.config
        config.keepOnlyVirtual = false
        let s = SessionRig(config: config)
        let uu = FakeUU(rig: s, lossOffsets: [])
        uu.at(21.144, true)
        uu.at(30, false)
        uu.at(33, true)
        uu.at(50, false, end: true)
        s.startTicking(at: 20.226)
        s.run(until: 120)
        #expect(s.trippedAt == nil)
        #expect(s.driver.count("create") == 1)     // 33s 重连落在 10s 宽限内，直接复用
        #expect(s.driver.count("disable") == 0)
    }
}
