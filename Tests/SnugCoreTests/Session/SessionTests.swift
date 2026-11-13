import Foundation
import Testing
@testable import SnugCore

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
}
