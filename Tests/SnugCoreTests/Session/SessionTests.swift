import Foundation
import Testing
@testable import SnugCore


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
    private let present = UUSignals(overlayVisible: false, controllers: .shown(["iPhone"]), captureActive: nil)
    private let absent = UUSignals(overlayVisible: false, controllers: .unrecognized, captureActive: nil)

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
        _ = s.update(UUSignals(overlayVisible: true, controllers: .unreadable, captureActive: nil), now: at(0))
        #expect(s.update(present, now: at(0.5)) == [.controllerChanged("iPhone")])
        #expect(s.controller == "iPhone")
    }

    @Test("回归 #1：没认出控制端、推流一直在，远程不断开；停流后照常 interrupted、ended")
    func unrecognizedTableKeepsStreamingSession() {
        var s = RemoteSession()
        let streaming = UUSignals(overlayVisible: false, controllers: .unrecognized, captureActive: true)
        let stopped = UUSignals(overlayVisible: false, controllers: .unrecognized, captureActive: false)
        #expect(s.update(streaming, now: at(0)) == [.began(controller: nil)])
        for seconds in [0.5, 59.5, 60, 60.5, 75.6, 300] {
            #expect(s.update(streaming, now: at(seconds)) == [])
        }
        #expect(s.wantsPhoneScreen(now: at(300)))
        #expect(s.update(stopped, now: at(300.5)) == [])
        #expect(s.update(stopped, now: at(301.6)) == [.interrupted])
        #expect(s.update(stopped, now: at(316.7)) == [.ended])
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

@Suite("要不要手机屏 RemoteSession.wantsPhoneScreen")
struct PhoneDemandTests {
    private let overlayOnly = UUSignals(overlayVisible: true, controllers: .unrecognized, captureActive: nil)
    private let absent = UUSignals(overlayVisible: false, controllers: .unrecognized, captureActive: nil)

    @Test("电脑控制端：断开后的重连窗口里也不要（断开那一拍名字被清空，不能当成手机）")
    func computerStaysComputerWhileReconnecting() {
        var s = RemoteSession()
        _ = s.update(table("DESKTOP-7Q2K1LM"), now: at(0))
        #expect(!s.wantsPhoneScreen(now: at(0)))
        _ = s.update(absent, now: at(1))
        #expect(s.update(absent, now: at(2)) == [.interrupted])
        #expect(s.controller == nil)
        #expect(s.inEpisode)
        #expect(!s.wantsPhoneScreen(now: at(2)))
        #expect(!s.wantsPhoneScreen(now: at(16)))
        #expect(s.update(absent, now: at(17.1)) == [.ended])
        #expect(s.episodeController == nil)
    }

    @Test("手机控制端：重连窗口里照样要，手机屏和上面的窗口留着")
    func phoneKeepsScreenWhileReconnecting() {
        var s = RemoteSession()
        _ = s.update(table("iPhone"), now: at(0))
        _ = s.update(absent, now: at(1))
        _ = s.update(absent, now: at(2))
        #expect(s.wantsPhoneScreen(now: at(10)))
        _ = s.update(absent, now: at(17.1))
        #expect(!s.wantsPhoneScreen(now: at(17.1)))
    }

    @Test("刚连上名字还没读到：先等 2 秒；名字下一拍读到是电脑，就一直不要")
    func waitsForNameThenComputer() {
        var s = RemoteSession()
        #expect(s.update(overlayOnly, now: at(0)) == [.began(controller: nil)])
        #expect(!s.wantsPhoneScreen(now: at(0)))
        #expect(s.update(UUSignals(overlayVisible: true, controllers: .shown(["MacBook Air"]), captureActive: nil), now: at(0.5))
                == [.controllerChanged("MacBook Air")])
        #expect(!s.wantsPhoneScreen(now: at(0.5)))
        #expect(!s.wantsPhoneScreen(now: at(5)))
    }

    @Test("一直没拿到名字（表格读不到或没认出控制端）：等满 2 秒后按手机处理", arguments: [ControllerTable.unreadable, .unrecognized])
    func namelessGetsScreenAfterGrace(table: ControllerTable) {
        var s = RemoteSession()
        _ = s.update(UUSignals(overlayVisible: true, controllers: table, captureActive: nil), now: at(0))
        #expect(!s.wantsPhoneScreen(now: at(1.9)))
        #expect(s.wantsPhoneScreen(now: at(2)))
    }

    @Test("不在远程里：不要")
    func idle() {
        #expect(!RemoteSession().wantsPhoneScreen(now: at(0)))
    }
}

