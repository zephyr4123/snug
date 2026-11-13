import Foundation
import Testing
@testable import SnugCore

/// 时间都写成「距 t0 的秒数」，断言里的数字能直接对上 1.5s 防抖、5s 静默期、60s 上限
private func at(_ s: Double) -> Date { t0.addingTimeInterval(s) }

private let none = UUSignals(overlayVisible: false, controllers: [], captureActive: false)
private let overlay = UUSignals(overlayVisible: true, controllers: nil, captureActive: nil)
private func table(_ names: String...) -> UUSignals { UUSignals(overlayVisible: false, controllers: names, captureActive: nil) }
private func capture(_ on: Bool?) -> UUSignals { UUSignals(overlayVisible: false, controllers: nil, captureActive: on) }

@Suite("连接判定 ConnectionTracker")
struct ConnectionTrackerTests {
    @Test("常量：防抖 1.5s、自扰静默期 5s、推流否决上限 60s")
    func constants() {
        #expect(ConnectionTracker.disconnectDebounce == 1.5)
        #expect(ConnectionTracker.quietWindow == 5)
        #expect(ConnectionTracker.maxCaptureVeto == 60)
    }

    @Test("在场 = 覆盖窗口 || 控制端非空 || 推流为 true；nil 与 [] 都不算在场")
    func presence() {
        #expect(overlay.isPresent)
        #expect(table("iPhone").isPresent)
        #expect(capture(true).isPresent)
        #expect(!none.isPresent)
        #expect(!UUSignals(overlayVisible: false, controllers: nil, captureActive: nil).isPresent)
    }

    @Test("首连不做确认延迟：第一次看到在场就连入，名字取 controllers.first")
    func immediateConnect() {
        var t = ConnectionTracker()
        #expect(t.update(none, now: at(0)) == nil)
        #expect(t.update(table("iPhone", "iPad"), now: at(0.5)) == .connected(controller: "iPhone"))
        #expect(t.isConnected)
        #expect(t.controller == "iPhone")

        var o = ConnectionTracker()
        #expect(o.update(overlay, now: at(0)) == .connected(controller: nil))
        var c = ConnectionTracker()
        #expect(c.update(capture(true), now: at(0)) == .connected(controller: nil))
    }

    @Test("断开防抖：最后一次在场之后超过 1.5s 才判断开")
    func debounce() {
        var t = ConnectionTracker()
        _ = t.update(table("iPhone"), now: at(0))
        #expect(t.update(none, now: at(0.5)) == nil)
        #expect(t.update(none, now: at(1.0)) == nil)
        #expect(t.update(none, now: at(1.5)) == nil)
        #expect(t.update(none, now: at(1.6)) == .disconnected)
        #expect(!t.isConnected)
        #expect(t.controller == nil)
        // 断开后再出现立刻连入
        #expect(t.update(overlay, now: at(1.7)) == .connected(controller: nil))
    }

    @Test("中途短暂缺席（<1.5s）不断开")
    func shortGap() {
        var t = ConnectionTracker()
        _ = t.update(overlay, now: at(0))
        #expect(t.update(none, now: at(1.0)) == nil)
        #expect(t.update(overlay, now: at(1.4)) == nil)
        #expect(t.update(none, now: at(2.8)) == nil)
        #expect(t.update(none, now: at(2.95)) == .disconnected)
    }

    @Test("自扰静默期：本工具引起扰动后 5s 内不判断开，过了才判")
    func quietWindow() {
        var t = ConnectionTracker()
        _ = t.update(table("iPhone"), now: at(0))
        t.noteSelfInducedChange(at: at(0.2))
        #expect(t.update(none, now: at(2.0)) == nil)   // 防抖已满足，但还在静默期
        #expect(t.update(none, now: at(5.2)) == nil)   // 0.2 + 5 = 5.2，还没「过」
        #expect(t.update(none, now: at(5.3)) == .disconnected)
    }

    @Test("静默期不拖慢连入")
    func quietDoesNotDelayConnect() {
        var t = ConnectionTracker()
        t.noteSelfInducedChange(at: at(0))
        #expect(t.update(overlay, now: at(0.1)) == .connected(controller: nil))
    }

    @Test("推流仍在时其余信号缺席也不断开；推流结束后从最后一次在场起 1.5s 判断开")
    func captureVetoThenEnd() {
        var t = ConnectionTracker()
        _ = t.update(UUSignals(overlayVisible: false, controllers: ["iPhone"], captureActive: true), now: at(0))
        for s in stride(from: 0.5, through: 10.0, by: 0.5) {
            #expect(t.update(capture(true), now: at(s)) == nil)
        }
        #expect(t.update(capture(false), now: at(10.5)) == nil)
        #expect(t.update(capture(false), now: at(11.5)) == nil)   // 距最后在场 10.0 恰 1.5
        #expect(t.update(capture(false), now: at(11.6)) == .disconnected)
    }

    @Test("推流卡在 true：其余信号连续缺席超过 60s 判断开，之后卡住的 true 不再算在场，推流重新开始才算")
    func captureVetoCap() {
        var t = ConnectionTracker()
        _ = t.update(UUSignals(overlayVisible: true, controllers: ["iPhone"], captureActive: true), now: at(0))
        #expect(t.update(capture(true), now: at(30)) == nil)
        #expect(t.update(capture(true), now: at(60)) == nil)
        #expect(t.update(capture(true), now: at(60.1)) == .disconnected)
        #expect(t.update(capture(true), now: at(61)) == nil)
        #expect(t.update(capture(true), now: at(120)) == nil)
        #expect(t.update(capture(false), now: at(121)) == nil)
        #expect(t.update(capture(true), now: at(122)) == .connected(controller: nil))
    }

    @Test("推流否决上限也要等过静默期")
    func captureCapRespectsQuiet() {
        var t = ConnectionTracker()
        _ = t.update(UUSignals(overlayVisible: true, controllers: nil, captureActive: true), now: at(0))
        t.noteSelfInducedChange(at: at(58))
        #expect(t.update(capture(true), now: at(61)) == nil)
        #expect(t.update(capture(true), now: at(63.1)) == .disconnected)
    }

    @Test("控制端名字：先没有后出现、或换人，发 controllerChanged；读不到时保留原名")
    func controllerChanges() {
        var t = ConnectionTracker()
        #expect(t.update(overlay, now: at(0)) == .connected(controller: nil))
        #expect(t.update(UUSignals(overlayVisible: true, controllers: ["iPad"], captureActive: nil), now: at(0.5)) == .controllerChanged("iPad"))
        #expect(t.update(UUSignals(overlayVisible: true, controllers: ["iPad"], captureActive: nil), now: at(1.0)) == nil)
        #expect(t.update(UUSignals(overlayVisible: true, controllers: ["iPhone"], captureActive: nil), now: at(1.5)) == .controllerChanged("iPhone"))
        #expect(t.update(UUSignals(overlayVisible: true, controllers: [], captureActive: nil), now: at(2.0)) == nil)
        #expect(t.controller == "iPhone")
    }

    @Test("信号快照写进日志用的描述：区分读不到 / 明确无人 / 具体名字")
    func snapshotDescription() {
        #expect(UUSignals(overlayVisible: true, controllers: nil, captureActive: nil).description == "overlay=是 控制端=读不到 capture=未知")
        #expect(UUSignals(overlayVisible: false, controllers: [], captureActive: false).description == "overlay=否 控制端=无 capture=否")
        #expect(UUSignals(overlayVisible: false, controllers: ["iPhone", "iPad"], captureActive: true).description == "overlay=否 控制端=iPhone,iPad capture=是")
    }
}
