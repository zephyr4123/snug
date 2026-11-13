import Foundation
import Testing
@testable import SnugCore

private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
private func at(_ s: Double) -> Date { t0.addingTimeInterval(s) }

@Suite("会话 SessionEpisode")
struct SessionEpisodeTests {
    @Test("重连窗口 15s")
    func window() { #expect(SessionEpisode.reconnectWindow == 15) }

    @Test("连入开始会话；断开后 15s 内再连入算同一会话，超过窗口会话结束")
    func lifecycle() {
        var e = SessionEpisode()
        #expect(!e.isActive)
        #expect(e.connected(at: at(0)) == .began)
        #expect(e.disconnected(at: at(10)) == .interrupted)
        #expect(e.isActive)
        #expect(e.advance(to: at(24.9)) == nil)
        #expect(e.connected(at: at(25)) == .resumed)   // 10 + 15 = 25，还在窗口内
        #expect(e.disconnected(at: at(30)) == .interrupted)
        #expect(e.advance(to: at(45)) == nil)
        #expect(e.advance(to: at(45.1)) == .ended)
        #expect(!e.isActive)
        #expect(e.connected(at: at(50)) == .began)
    }

    @Test("窗口过了才来的连入：先结束旧会话，再开始新会话")
    func lateReconnect() {
        var e = SessionEpisode()
        _ = e.connected(at: at(0))
        _ = e.disconnected(at: at(1))
        #expect(e.advance(to: at(17)) == .ended)
        #expect(e.connected(at: at(17)) == .began)
    }

    @Test("手动叫停只在会话进行中生效，作用到本会话结束（修 B11）")
    func manualSuspend() {
        var e = SessionEpisode()
        // 不在会话中：只是恢复一下，不影响下一次远程
        #expect(e.suspendByUser() == false)
        #expect(e.suspendedByUser == false)
        _ = e.connected(at: at(0))
        #expect(e.suspendedByUser == false)

        #expect(e.suspendByUser() == true)
        #expect(e.suspendedByUser)
        _ = e.disconnected(at: at(5))
        _ = e.connected(at: at(10))          // 窗口内重连：同一会话，标记保留
        #expect(e.suspendedByUser)
        _ = e.disconnected(at: at(20))
        #expect(e.advance(to: at(40)) == .ended)
        #expect(e.suspendedByUser == false)
        _ = e.connected(at: at(50))
        #expect(e.suspendedByUser == false)
    }

    @Test("重连窗口里按手动叫停也算会话进行中")
    func suspendDuringWindow() {
        var e = SessionEpisode()
        _ = e.connected(at: at(0))
        _ = e.disconnected(at: at(1))
        #expect(e.suspendByUser() == true)
        _ = e.connected(at: at(3))
        #expect(e.suspendedByUser)
    }
}

@Suite("远程会话 RemoteSession")
struct RemoteSessionTests {
    private let present = UUSignals(overlayVisible: false, controllers: ["iPhone"], captureActive: nil)
    private let absent = UUSignals(overlayVisible: false, controllers: [], captureActive: nil)

    @Test("连入 → began；断开 → interrupted；窗口内重连 → resumed；窗口过后 → ended")
    func transitions() {
        var s = RemoteSession()
        #expect(s.update(present, now: at(0)) == [.began(controller: "iPhone")])
        #expect(s.update(absent, now: at(1.0)) == [])
        #expect(s.update(absent, now: at(2.0)) == [.interrupted])
        #expect(s.isConnected == false)
        #expect(s.inEpisode)
        #expect(s.update(present, now: at(3.0)) == [.resumed(controller: "iPhone")])
        #expect(s.update(absent, now: at(5.0)) == [.interrupted])
        #expect(s.update(absent, now: at(20.0)) == [])
        #expect(s.update(absent, now: at(20.1)) == [.ended])
        #expect(!s.inEpisode)
    }

    @Test("窗口过后同一拍又连上：先 ended 再 began")
    func endedThenBegan() {
        var s = RemoteSession()
        _ = s.update(present, now: at(0))
        _ = s.update(absent, now: at(2.0))
        #expect(s.update(present, now: at(30)) == [.ended, .began(controller: "iPhone")])
    }

    @Test("控制端换名透传为 controllerChanged")
    func controllerChanged() {
        var s = RemoteSession()
        _ = s.update(UUSignals(overlayVisible: true, controllers: nil, captureActive: nil), now: at(0))
        #expect(s.update(present, now: at(0.5)) == [.controllerChanged("iPhone")])
        #expect(s.controller == "iPhone")
    }

    @Test("自扰静默期经 RemoteSession 转给 tracker")
    func selfInduced() {
        var s = RemoteSession()
        _ = s.update(present, now: at(0))
        s.noteSelfInducedChange(at: at(0))
        #expect(s.update(absent, now: at(4.0)) == [])
        #expect(s.update(absent, now: at(5.1)) == [.interrupted])
    }

    @Test("手动叫停：会话外无效，会话内到会话结束为止")
    func suspend() {
        var s = RemoteSession()
        #expect(s.suspendByUser() == false)
        _ = s.update(present, now: at(0))
        #expect(s.suspendByUser() == true)
        #expect(s.suspendedByUser)
        _ = s.update(absent, now: at(2))
        _ = s.update(absent, now: at(20))
        #expect(s.suspendedByUser == false)
    }
}
