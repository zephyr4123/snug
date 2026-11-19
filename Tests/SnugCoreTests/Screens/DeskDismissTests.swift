import CoreGraphics
import Testing
@testable import SnugCore

@Suite("一块屏的调度：在手机上退出这块屏")
@MainActor
struct DeskDismissTests {
    @Test("退出手机屏：先缩回字号，撤屏后放回原位；这次远程不再加")
    func dismiss() async throws {
        let rig = try Rig()
        await rig.ready()
        await rig.pull(ghostty)
        rig.journal.clear()
        rig.timeline.advance(10)
        rig.desk.dismissScreen()
        await rig.desk.idle()
        #expect(rig.journal.all == [
            "zoom 7 -2 ✎", "snapshot", "retire 101", "restore except 7",
            "move 7 \(ghosttyHome.short) ✎",
        ])
        #expect(rig.record == nil)
        #expect(rig.desk.state.screen == .off)
        #expect(rig.desk.state.dismissed)
        // 会话层每拍照旧说「要」：不再加
        rig.desk.setWanted(true)
        await rig.desk.idle()
        #expect(!rig.journal.all.contains("create"))
    }

    @Test("退出的过程讲得清：整屏写明正在退出（列表点不了），撤完回到空闲")
    func showsProgress() async throws {
        let rig = try Rig()
        await rig.ready()
        rig.timeline.advance(10)
        rig.desk.dismissScreen()
        #expect(rig.desk.state.work == .dismissing)
        await rig.desk.idle()
        #expect(rig.desk.state.work == nil)
    }

    @Test("这次远程结束（不再要手机屏），下次远程照常加屏")
    func nextEpisode() async throws {
        let rig = try Rig()
        await rig.ready()
        rig.timeline.advance(10)
        rig.desk.dismissScreen()
        await rig.desk.idle()
        rig.desk.setWanted(false)
        await rig.desk.idle()
        #expect(!rig.desk.state.dismissed)
        rig.desk.setWanted(true)
        await rig.desk.idle()
        #expect(rig.desk.state.screen == .ready(102))
    }

    @Test("上一次远程结束、下一次开始落在同一拍（AppController 先说「不要」再说「要」）：退出不带进下一次")
    func episodeEndsAndBeginsInOneTick() async throws {
        let rig = try Rig()
        await rig.ready()
        rig.timeline.advance(10)
        rig.desk.dismissScreen()
        await rig.desk.idle()
        rig.desk.setWanted(false)
        rig.desk.setWanted(true)
        await rig.desk.idle()
        #expect(!rig.desk.state.dismissed)
        #expect(rig.desk.state.screen == .ready(102))
    }

    @Test("撤屏跑到一半又要回这块屏（关了马上又开、断线判结束后几秒内又连上）：重建出来的屏照样有 Desk")
    func rewantedWhileRetiring() async throws {
        let rig = try Rig()
        await rig.ready()
        rig.timeline.advance(10)
        rig.desk.setWanted(false)
        // 等撤屏真的开始（第一次撤屏的对账已经拷下「不要这块屏」的目标），再要回来
        for _ in 0..<200 where !rig.journal.all.contains(where: { $0.hasPrefix("retire") }) { await Task.yield() }
        #expect(rig.journal.all.contains(where: { $0.hasPrefix("retire") }))
        rig.desk.setWanted(true)
        await rig.desk.idle()
        #expect(rig.desk.state.screen == .ready(102))
        #expect(rig.set.state.desks[.phone] != nil)
        await rig.pull(ghostty)
        #expect(rig.desk.state.placed?.window == ghostty)
    }

    @Test("没退出时同一拍里先「不要」再「要」：手机屏不撤也不重建，放着的窗口照旧")
    func falseThenTrueKeepsScreen() async throws {
        let rig = try Rig()
        await rig.ready()
        await rig.pull(ghostty)
        rig.journal.clear()
        rig.desk.setWanted(false)
        rig.desk.setWanted(true)
        await rig.desk.idle()
        #expect(rig.journal.all.isEmpty)
        #expect(rig.desk.state.placed?.window == ghostty)
    }

    @Test("排在退出后面的放窗口：屏已经撤了，什么都不做；下一次加的屏上没有旧提示")
    func staleNoticeClearedOnNewScreen() async throws {
        let rig = try Rig()
        await rig.ready()
        rig.timeline.advance(10)
        rig.desk.dismissScreen()
        rig.desk.pull(ghostty)
        await rig.desk.idle()
        #expect(rig.set.state.desks[.phone] == nil)
        rig.desk.setWanted(false)
        rig.desk.setWanted(true)
        await rig.desk.idle()
        #expect(rig.desk.state.notice == nil)
    }

    @Test("远程刚结束、屏还没撤完时点了退出：不算数，下次远程照常加屏")
    func afterEpisodeEnded() async throws {
        let rig = try Rig()
        await rig.ready()
        rig.desk.setWanted(false)
        rig.desk.dismissScreen()
        await rig.desk.idle()
        #expect(!rig.desk.state.dismissed)
        rig.desk.setWanted(true)
        await rig.desk.idle()
        #expect(rig.desk.state.screen == .ready(102))
    }
}
