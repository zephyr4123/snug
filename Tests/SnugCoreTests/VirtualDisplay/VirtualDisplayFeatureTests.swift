import Foundation
import Testing
@testable import SnugCore

@Suite("熄屏不稳定熔断 PhysicalOffBreaker")
struct PhysicalOffBreakerTests {
    @Test("断开时物理屏关着、重连窗口内又连上 → 跳闸；会话结束或新会话开始复位")
    func trips() {
        var b = PhysicalOffBreaker()
        b.handle(.began(controller: "iPhone"), physicalOff: false)
        b.handle(.interrupted, physicalOff: true)
        #expect(b.allowsPhysicalOff)
        b.handle(.resumed(controller: "iPhone"), physicalOff: false)
        #expect(b.tripped)
        #expect(!b.allowsPhysicalOff)
        b.handle(.interrupted, physicalOff: false)
        b.handle(.resumed(controller: "iPhone"), physicalOff: false)
        #expect(b.tripped)                       // 本会话一直保持
        b.handle(.ended, physicalOff: false)
        #expect(!b.tripped)
    }

    @Test("断开时物理屏本来就亮着：重连不跳闸")
    func noTripWhenPhysicalOn() {
        var b = PhysicalOffBreaker()
        b.handle(.began(controller: nil), physicalOff: false)
        b.handle(.interrupted, physicalOff: false)
        b.handle(.resumed(controller: nil), physicalOff: false)
        #expect(!b.tripped)
    }
}

@Suite("虚拟屏功能模块：会话闭环")
@MainActor
struct VirtualDisplayFeatureTests {
    private let present = UUSignals(overlayVisible: true, controllers: ["iPhone"], captureActive: nil)

    @Test("功能关着（默认）：连上也什么都不做")
    func disabledByDefault() {
        var config = SessionRig.config
        config.virtualDisplayEnabled = false
        let s = SessionRig(config: config)
        s.signals = { present }
        s.startTicking(at: 0)
        s.run(until: 20)
        #expect(s.session.isConnected)
        #expect(s.driver.calls.isEmpty)
    }

    @Test("控制端不在设备列表、是电脑、或没填分辨率：不建屏")
    func unknownOrUnsizedDevice() {
        var config = SessionRig.config
        config.devices = [DeviceProfile(name: "iPhone", kind: .phone, width: 0, height: 0),
                          DeviceProfile(name: "M1", kind: .computer, width: 2560, height: 1600)]
        let s = SessionRig(config: config)
        var name = "iPhone"
        s.signals = { UUSignals(overlayVisible: true, controllers: [name], captureActive: nil) }
        s.startTicking(at: 0)
        s.run(until: 5)
        name = "M1"
        s.run(until: 10)
        name = "陌生设备"
        s.run(until: 15)
        #expect(s.driver.count("create") == 0)
    }

    @Test("名字晚到：先连上不建屏，名字出现后再建")
    func lateName() {
        let s = SessionRig()
        var names: [String]? = nil
        s.signals = { UUSignals(overlayVisible: true, controllers: names, captureActive: nil) }
        s.startTicking(at: 0)
        s.run(until: 3)
        #expect(s.driver.count("create") == 0)
        names = ["iPhone"]
        s.run(until: 10)
        #expect(near(s.driver.names("create").first.map { $0.at.timeIntervalSince(t0) }, 3.5))  // 3.0 那拍名字还没到
    }

    @Test("会话中按热键：本会话不再关物理屏，重连也保持；会话结束后下一次远程照常关")
    func manualRestoreInSession() {
        let s = SessionRig()
        var on = true
        s.signals = { on ? present : UUSignals(overlayVisible: false, controllers: [], captureActive: nil) }
        s.startTicking(at: 0)
        s.run(until: 10)
        #expect(s.driver.count("disable") == 1)
        #expect(s.pressRestoreHotkey())
        s.run(until: 20)
        #expect(s.driver.count("enable") == 1)
        #expect(s.driver.count("disable") == 1)
        on = false
        s.run(until: 23)              // 断开（静默期早已过去）
        on = true
        s.run(until: 30)              // 窗口内重连：仍不关
        #expect(s.driver.count("disable") == 1)
        on = false
        s.run(until: 60)              // 会话结束
        on = true
        s.run(until: 80)
        #expect(s.driver.count("disable") == 2)
    }

    @Test("不在会话中按热键只恢复物理屏，不影响下一次远程（修 B11）")
    func manualRestoreOutsideSession() {
        let s = SessionRig()
        var on = false
        s.signals = { on ? present : UUSignals(overlayVisible: false, controllers: [], captureActive: nil) }
        s.startTicking(at: 0)
        s.run(until: 2)
        #expect(!s.pressRestoreHotkey())
        on = true
        s.run(until: 15)
        #expect(s.driver.count("disable") == 1)
    }

    @Test("真实断开：推流结束 + 其余信号缺席 → 1.5s 后判断开 → 立刻恢复物理屏 → 10s 后释放虚拟屏 → 还原布局 → 删 layout.json")
    func realDisconnect() {
        let s = SessionRig()
        var capture = true
        s.signals = {
            capture ? UUSignals(overlayVisible: false, controllers: ["iPhone"], captureActive: true)
                    : UUSignals(overlayVisible: false, controllers: [], captureActive: false)
        }
        s.startTicking(at: 0)
        s.run(until: 30)
        #expect(s.driver.count("disable") == 1)
        capture = false                                   // 30.0 起推流停、表格空
        s.run(until: 60)
        let disconnect = s.times(.interrupted).first
        #expect(near(disconnect, 30.0 + 2.0))             // 30.0 那拍还在场；之后缺席 >1.5s 的第一拍是 32.0
        #expect(near(s.rig.first("enable"), disconnect ?? -1))
        #expect(near(s.rig.first("release"), (disconnect ?? -1) + 10))
        let release = s.rig.first("release") ?? -1
        #expect(near(s.rig.first("restoreModes"), release + 0.09 + 1.5))
        #expect(near(s.rig.first("restoreOrigins"), release + 0.09 + 1.5 + 0.08 + 0.5))
        #expect(!s.driver.layoutRecord)
        #expect(s.driver.virtualCount == 0)
        #expect(!s.feature.breaker.tripped)
    }

    @Test("推流卡在 true：其余信号缺席超过 60s 后按上限判断开，物理屏恢复")
    func stuckCapture() {
        let s = SessionRig()
        var others = true
        s.signals = { UUSignals(overlayVisible: false, controllers: others ? ["iPhone"] : [], captureActive: true) }
        s.startTicking(at: 0)
        s.run(until: 10)
        others = false                                    // 10.0 起只剩推流
        s.run(until: 69.5)
        #expect(s.times(.interrupted).isEmpty)
        s.run(until: 80)
        #expect(near(s.times(.interrupted).first, 10.0 + 60 + 0.5))  // 最后一次表格在场 10.0，缺席 >60s 的第一拍
        #expect(s.driver.count("enable") == 1)
    }
}
