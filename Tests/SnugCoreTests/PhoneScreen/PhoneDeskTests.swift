import CoreGraphics
import Foundation
import Testing
@testable import SnugCore

private let ghostty = WindowInfo(key: WindowKey(pid: 10, id: 7), app: "Ghostty", bundleID: "com.mitchellh.ghostty", title: "~/snug")
private let finder = WindowInfo(key: WindowKey(pid: 11, id: 8), app: "Finder", bundleID: "com.apple.finder", title: "下载")
private let safari = WindowInfo(key: WindowKey(pid: 12, id: 9), app: "Safari", bundleID: "com.apple.Safari", title: "GitHub")
private let ghosttyHome = CGRect(x: 100, y: 100, width: 1200, height: 800)
private let finderHome = CGRect(x: 300, y: 200, width: 800, height: 500)
private let safariHome = CGRect(x: 0, y: 25, width: 1512, height: 920)
private let phoneArea = CGRect(x: 2000, y: 25, width: 540, height: 897)

/// 一套假系统 + 一个 PhoneDesk。每个用例一个临时数据目录
@MainActor
private final class Rig {
    let dir: URL
    let paths: SnugPaths
    let journal = Journal()
    let displays: FakeDisplays
    let windows: FakeWindows
    let timeline = ManualTimeline()
    let desk: PhoneDesk

    init(dataDirectory: URL? = nil) throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("snug-desk-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        paths = SnugPaths(dataDirectory: dataDirectory ?? dir, logFile: dir.appendingPathComponent("Snug.log"))
        displays = FakeDisplays(journal: journal)
        windows = FakeWindows(journal: journal, ledger: paths.phoneRecord)
        windows.add(ghostty.key, frame: ghosttyHome)
        windows.add(finder.key, frame: finderHome)
        windows.add(safari.key, frame: safariHome, fullScreen: true)
        desk = PhoneDesk(displays: displays, windows: windows, timeline: timeline, paths: paths)
    }

    deinit { try? FileManager.default.removeItem(at: dir) }

    var record: PhoneRecord? { RestoreRecord<PhoneRecord>(url: paths.phoneRecord).pending() }

    /// 加好手机屏，流水账清空
    func ready() async {
        desk.setWanted(true)
        await desk.idle()
        journal.clear()
    }

    func pull(_ w: WindowInfo) async {
        desk.pull(w)
        await desk.idle()
    }
}

@Suite("手机屏调度 PhoneDesk")
@MainActor
struct PhoneDeskTests {
    @Test("要手机屏：加屏前给窗口拍快照，加好后把被系统拉走的窗口放回去；默认竖屏、显示窗口列表")
    func addScreen() async throws {
        let rig = try Rig()
        // macOS 会把上次留在这块屏上的窗口拉过去
        rig.displays.onCreate = { rig.windows.setFrame(finder.key, phoneArea) }
        rig.desk.setWanted(true)
        await rig.desk.idle()
        #expect(rig.journal.all == ["snapshot", "create portrait", "restore"])
        #expect(rig.windows.window(finder.key)?.frame == finderHome)
        #expect(rig.desk.state.screen == .ready(101))
        #expect(rig.desk.state.listVisible)
        #expect(rig.desk.state.orientation == .portrait)
    }

    @Test("同一个结论重复传不重复动手")
    func wantedIsIdempotent() async throws {
        let rig = try Rig()
        rig.desk.setWanted(true)
        rig.desk.setWanted(true)
        await rig.desk.idle()
        #expect(rig.journal.all.filter { $0.hasPrefix("create") }.count == 1)
    }

    @Test("放一个窗口：先记账再挪，挪到手机屏铺满、激活它，按默认级数放大字号，列表收起")
    func pullWindow() async throws {
        let rig = try Rig()
        await rig.ready()
        await rig.pull(ghostty)
        #expect(rig.journal.all == ["move 7 \(phoneArea.short) ✎", "focus 7", "zoom 7 +2 ✎"])
        #expect(rig.windows.window(ghostty.key)?.zoom == 2)
        #expect(rig.desk.state.placed?.window == ghostty)
        #expect(rig.desk.state.placed?.zoom == 2)
        #expect(rig.desk.state.listVisible == false)
        #expect(rig.desk.state.work == nil)
        #expect(rig.record == PhoneRecord(window: ghostty.key, label: ghostty.label, original: ghosttyHome, wasFullScreen: false, zoom: 2))
    }

    @Test("不在调字号名单里的 App 不发 ⌘=")
    func noZoomForOtherApps() async throws {
        let rig = try Rig()
        await rig.ready()
        await rig.pull(finder)
        #expect(!rig.journal.all.contains { $0.hasPrefix("zoom") })
        #expect(rig.desk.state.placed?.zoomable == false)
    }

    @Test("换一个窗口：旧窗口先缩回字号、回原位，再放新的")
    func switchWindows() async throws {
        let rig = try Rig()
        await rig.ready()
        await rig.pull(ghostty)
        rig.journal.clear()
        await rig.pull(finder)
        #expect(rig.journal.all == [
            "zoom 7 -2 ✎", "move 7 \(ghosttyHome.short) ✎",
            "move 8 \(phoneArea.short) ✎", "focus 8",
        ])
        #expect(rig.windows.window(ghostty.key)?.frame == ghosttyHome)
        #expect(rig.windows.window(ghostty.key)?.zoom == 0)
        #expect(rig.record?.window == finder.key)
    }

    @Test("原来全屏的窗口：先退出全屏再读原位，放回时恢复全屏")
    func fullScreenWindow() async throws {
        let rig = try Rig()
        await rig.ready()
        await rig.pull(safari)
        #expect(rig.journal.all.prefix(2) == ["fullscreen 9 off", "move 9 \(phoneArea.short) ✎"])
        #expect(rig.record?.wasFullScreen == true)
        rig.journal.clear()
        rig.desk.putBack()
        await rig.desk.idle()
        #expect(rig.journal.all == ["move 9 \(safariHome.short) ✎", "fullscreen 9 on"])
        #expect(rig.windows.window(safari.key)?.fullScreen == true)
        #expect(rig.record == nil)
        #expect(rig.desk.state.placed == nil)
        #expect(rig.desk.state.listVisible)
    }

    @Test("点手机屏上已经在的那个窗口：只是回到它，不重新放")
    func pullSameWindowReturns() async throws {
        let rig = try Rig()
        await rig.ready()
        await rig.pull(ghostty)
        rig.desk.showList()
        rig.journal.clear()
        await rig.pull(ghostty)
        #expect(rig.journal.all == ["focus 7"])
        #expect(rig.desk.state.listVisible == false)
    }

    @Test("横过来：先撤旧屏再建横屏，窗口挪到新屏，字号不重复放大，直接回到窗口")
    func rotate() async throws {
        let rig = try Rig()
        await rig.ready()
        await rig.pull(ghostty)
        rig.desk.showList()
        rig.journal.clear()
        rig.timeline.advance(10)
        rig.desk.rotate()
        await rig.desk.idle()
        #expect(rig.journal.all == [
            "snapshot", "retire 101", "restore except 7",
            "snapshot", "create landscape", "restore except 7",
            "move 7 \(phoneArea.short) ✎", "focus 7",
        ])
        #expect(rig.desk.state.orientation == .landscape)
        #expect(rig.desk.state.screen == .ready(102))
        #expect(rig.windows.window(ghostty.key)?.zoom == 2)
        #expect(rig.desk.state.listVisible == false)
    }

    @Test("没放窗口时横过来：换成横屏，停在窗口列表")
    func rotateEmpty() async throws {
        let rig = try Rig()
        await rig.ready()
        rig.timeline.advance(10)
        rig.desk.rotate()
        await rig.desk.idle()
        #expect(rig.desk.state.orientation == .landscape)
        #expect(rig.desk.state.listVisible)
    }

    @Test("建好不到 2.5 秒就要撤：先等够再撤（太早释放会让 WindowServer 卡死）")
    func minimumLifetime() async throws {
        let rig = try Rig()
        await rig.ready()
        let before = rig.timeline.now
        rig.desk.setWanted(false)
        await rig.desk.idle()
        #expect(rig.timeline.now - before >= PhoneScreenSpec.minimumLifetime)
        #expect(rig.journal.all.contains("retire 101"))
    }

    @Test("不要手机屏了（会话结束）：窗口放回原位、字号缩回，再撤屏；记录销账，回到竖屏")
    func teardown() async throws {
        let rig = try Rig()
        await rig.ready()
        await rig.pull(ghostty)
        rig.desk.rotate()
        await rig.desk.idle()
        rig.journal.clear()
        rig.timeline.advance(10)
        rig.desk.setWanted(false)
        await rig.desk.idle()
        #expect(rig.journal.all == [
            "zoom 7 -2 ✎", "move 7 \(ghosttyHome.short) ✎",
            "snapshot", "retire 102", "restore",
        ])
        #expect(rig.windows.window(ghostty.key)?.frame == ghosttyHome)
        #expect(rig.record == nil)
        #expect(rig.desk.state.screen == .off)
        #expect(rig.desk.state.orientation == .portrait)
        #expect(rig.desk.state.placed == nil)
    }

    @Test("退出：shutdown 做完收尾才返回")
    func shutdown() async throws {
        let rig = try Rig()
        await rig.ready()
        await rig.pull(finder)
        await rig.desk.shutdown()
        #expect(rig.windows.window(finder.key)?.frame == finderHome)
        #expect(rig.desk.state.screen == .off)
        #expect(rig.record == nil)
    }

    @Test("字大一级：先记账再发按键，记到这个 App 名下，下次放上来按记住的级数")
    func zoomRemembered() async throws {
        let rig = try Rig()
        await rig.ready()
        await rig.pull(ghostty)
        rig.journal.clear()
        rig.desk.zoom(by: 1)
        await rig.desk.idle()
        #expect(rig.journal.all == ["zoom 7 +1 ✎"])
        #expect(rig.record?.zoom == 3)
        #expect(rig.desk.state.placed?.zoom == 3)

        await rig.pull(finder)
        rig.journal.clear()
        await rig.pull(ghostty)
        #expect(rig.journal.all.last == "zoom 7 +3 ✎")
        // 记在 zoom.json 里，重启也在
        let saved = JSONFile<ZoomBook>(url: rig.paths.zoomBook).loadOrQuarantine()
        #expect(saved?.steps(for: ghostty.bundleID, default: 0) == 3)
    }

    @Test("名单外的 App 点字大：什么都不做")
    func zoomIgnoredForOtherApps() async throws {
        let rig = try Rig()
        await rig.ready()
        await rig.pull(finder)
        rig.journal.clear()
        rig.desk.zoom(by: 1)
        await rig.desk.idle()
        #expect(rig.journal.all.isEmpty)
        #expect(rig.desk.state.work == nil)
    }

    @Test("设置里的默认级数改成 0：放上来不改字号")
    func defaultZoomZero() async throws {
        let rig = try Rig()
        rig.desk.defaultZoom = 0
        await rig.ready()
        await rig.pull(ghostty)
        #expect(!rig.journal.all.contains { $0.hasPrefix("zoom") })
    }

    @Test("还原记录写不进去：不挪窗口，告诉用户；原来全屏的恢复全屏")
    func ledgerFailureBlocksChange() async throws {
        let blocker = FileManager.default.temporaryDirectory.appendingPathComponent("snug-blocker-\(UUID().uuidString)")
        try Data().write(to: blocker)
        defer { try? FileManager.default.removeItem(at: blocker) }
        // 数据目录的位置是个普通文件，记录写不进去
        let rig = try Rig(dataDirectory: blocker.appendingPathComponent("data"))
        await rig.ready()
        await rig.pull(safari)
        #expect(rig.journal.all == ["fullscreen 9 off", "fullscreen 9 on"])
        #expect(rig.windows.window(safari.key)?.frame == safariHome)
        #expect(rig.desk.state.placed == nil)
        #expect(rig.desk.state.notice != nil)
        #expect(rig.desk.state.listVisible)
    }

    @Test("要放的窗口已经关了：告诉用户，什么都不动")
    func pullClosedWindow() async throws {
        let rig = try Rig()
        await rig.ready()
        rig.windows.close(finder.key)
        await rig.pull(finder)
        #expect(rig.desk.state.notice == "窗口已关闭")
        #expect(rig.record == nil)
        #expect(rig.desk.state.placed == nil)
    }

    @Test("手机屏上的窗口被关掉：定期核对时发现，回到窗口列表，记录作废")
    func placedWindowClosed() async throws {
        let rig = try Rig()
        await rig.ready()
        await rig.pull(ghostty)
        rig.windows.close(ghostty.key)
        rig.desk.verifyPlacement()
        await rig.desk.idle()
        #expect(rig.desk.state.placed == nil)
        #expect(rig.desk.state.listVisible)
        #expect(rig.record == nil)
    }

    @Test("辅助功能权限中途被收回：放不回去的窗口不当成已关，记录留着；核对、恢复都先等权限")
    func trustRevoked() async throws {
        let rig = try Rig()
        await rig.ready()
        await rig.pull(ghostty)
        rig.windows.revokeTrust()
        rig.desk.verifyPlacement()
        await rig.desk.idle()
        #expect(rig.desk.state.placed != nil)   // 看不到窗口不等于窗口关了
        rig.timeline.advance(10)
        rig.desk.setWanted(false)
        await rig.desk.idle()
        #expect(rig.record?.window == ghostty.key)
        #expect(rig.record?.original == ghosttyHome)
        rig.desk.recover()
        await rig.desk.idle()
        #expect(rig.record != nil)               // 没权限时不动记录
    }

    @Test("加屏失败：显示失败；不要了就回到关闭")
    func createFails() async throws {
        let rig = try Rig()
        rig.displays.createFails = true
        rig.desk.setWanted(true)
        await rig.desk.idle()
        #expect(rig.desk.state.screen == .failed)
        rig.desk.setWanted(false)
        await rig.desk.idle()
        #expect(rig.desk.state.screen == .off)
        #expect(!rig.journal.all.contains { $0.hasPrefix("retire") })
    }

    @Test("屏幕配置变了：过一会儿检查 2 倍，窗口不铺满了就重新铺满")
    func displaysChanged() async throws {
        let rig = try Rig()
        await rig.ready()
        await rig.pull(finder)
        rig.windows.setFrame(finder.key, CGRect(x: 2000, y: 25, width: 270, height: 448))
        rig.journal.clear()
        rig.desk.displaysChanged()
        rig.desk.displaysChanged()   // 连着来几次只查一回
        await rig.desk.idle()
        #expect(rig.journal.all == ["ensure 101", "move 8 \(phoneArea.short) ✎"])
    }

    @Test("上次崩溃留下的记录：窗口还在就缩回字号、放回原位、恢复全屏，然后销账")
    func recover() async throws {
        let rig = try Rig()
        rig.windows.setFrame(safari.key, CGRect(x: 0, y: 25, width: 540, height: 897))
        try RestoreRecord<PhoneRecord>(url: rig.paths.phoneRecord).record(
            PhoneRecord(window: safari.key, label: safari.label, original: safariHome, wasFullScreen: true, zoom: 2))
        rig.desk.recover()
        await rig.desk.idle()
        #expect(rig.journal.all == ["zoom 9 -2 ✎", "move 9 \(safariHome.short) ✎", "fullscreen 9 on"])
        #expect(rig.record == nil)
    }

    @Test("上次崩溃留下的记录，窗口已经不在了：记录作废，什么都不动")
    func recoverGoneWindow() async throws {
        let rig = try Rig()
        rig.windows.close(safari.key)
        try RestoreRecord<PhoneRecord>(url: rig.paths.phoneRecord).record(
            PhoneRecord(window: safari.key, label: safari.label, original: safariHome, wasFullScreen: true, zoom: 2))
        rig.desk.recover()
        await rig.desk.idle()
        #expect(rig.journal.all.isEmpty)
        #expect(rig.record == nil)
    }

    @Test("加屏、撤屏都先通知会话层（暂缓断开判定）")
    func topologyNotices() async throws {
        let rig = try Rig()
        var count = 0
        rig.desk.onTopologyChange = { count += 1 }
        await rig.ready()
        rig.timeline.advance(10)
        rig.desk.setWanted(false)
        await rig.desk.idle()
        #expect(count == 2)
    }

    @Test("状态变化推给界面")
    func publishesState() async throws {
        let rig = try Rig()
        var screens: [PhoneDesk.State.Screen] = []
        rig.desk.onChange = { state in
            if screens.last != state.screen { screens.append(state.screen) }
        }
        await rig.ready()
        #expect(screens == [.preparing, .ready(101)])
    }
}
