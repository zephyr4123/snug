import CoreGraphics
import Foundation
import Testing
@testable import SnugCore

private let ghostty = WindowInfo(key: WindowKey(pid: 10, id: 7), app: "Ghostty", bundleID: "com.mitchellh.ghostty", title: "~/snug")
private let finder = WindowInfo(key: WindowKey(pid: 11, id: 8), app: "Finder", bundleID: "com.apple.finder", title: "下载")
private let safari = WindowInfo(key: WindowKey(pid: 12, id: 9), app: "Safari", bundleID: "com.apple.Safari", title: "GitHub")
private let notes = WindowInfo(key: WindowKey(pid: 13, id: 10), app: "备忘录", bundleID: "com.apple.Notes", title: "清单")
private let ghosttyHome = CGRect(x: 100, y: 100, width: 1200, height: 800)
private let finderHome = CGRect(x: 300, y: 200, width: 800, height: 500)
private let safariHome = CGRect(x: 0, y: 25, width: 1512, height: 920)
/// Safari 退出全屏后的平时位置
private let safariWindowed = CGRect(x: 200, y: 100, width: 1000, height: 700)
private let notesHome = CGRect(x: 400, y: 300, width: 700, height: 500)
private let phoneArea = CGRect(x: 2000, y: 25, width: 540, height: 897)

/// 一套假系统 + 一个 PhoneDesk。每个用例一个临时数据目录
@MainActor
private final class Rig {
    private let tmp: TempDir
    let paths: SnugPaths
    let journal = Journal()
    let displays: FakeDisplays
    let windows: FakeWindows
    let timeline = ManualTimeline()
    let desk: PhoneDesk

    init(dataDirectory: URL? = nil) throws {
        let tmp = try TempDir()
        let dir = tmp.url
        self.tmp = tmp
        paths = SnugPaths(dataDirectory: dataDirectory ?? dir, logFile: dir.appendingPathComponent("Snug.log"))
        displays = FakeDisplays(journal: journal)
        windows = FakeWindows(journal: journal, ledger: paths.phoneRecord)
        windows.add(ghostty.key, frame: ghosttyHome)
        windows.add(finder.key, frame: finderHome)
        windows.add(safari.key, frame: safariHome, fullScreen: true, windowed: safariWindowed)
        windows.add(notes.key, frame: notesHome, minimized: true)
        desk = PhoneDesk(displays: displays, windows: windows, timeline: timeline, paths: paths)
        let timeline = timeline
        displays.clock = { timeline.now }
    }

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
    @Test("要手机屏：加屏前给窗口拍快照，加好后把被系统拉走的窗口放回去；显示窗口列表")
    func addScreen() async throws {
        let rig = try Rig()
        // macOS 会把上次留在这块屏上的窗口拉过去
        rig.displays.onCreate = { rig.windows.setFrame(finder.key, phoneArea) }
        rig.desk.setWanted(true)
        await rig.desk.idle()
        #expect(rig.journal.all == ["snapshot", "create", "restore"])
        #expect(rig.windows.window(finder.key)?.frame == finderHome)
        #expect(rig.desk.state.screen == .ready(101))
        #expect(rig.desk.state.listVisible)
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
        #expect(rig.record == PhoneRecord(window: ghostty.key, app: ghostty.app, label: ghostty.label, original: ghosttyHome, wasFullScreen: false, zoom: 2))
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

    @Test("原来全屏的窗口：先记账再退出全屏，原位改记成退出全屏后的平时位置；放回时回到那里再进全屏")
    func fullScreenWindow() async throws {
        let rig = try Rig()
        await rig.ready()
        await rig.pull(safari)
        #expect(rig.journal.all == ["fullscreen 9 off ✎", "move 9 \(phoneArea.short) ✎", "focus 9"])
        #expect(rig.record?.wasFullScreen == true)
        #expect(rig.record?.original == safariWindowed)
        rig.journal.clear()
        rig.desk.putBack()
        await rig.desk.idle()
        #expect(rig.journal.all == ["move 9 \(safariWindowed.short) ✎", "fullscreen 9 on ✎"])
        #expect(rig.windows.window(safari.key)?.fullScreen == true)
        #expect(rig.windows.window(safari.key)?.frame == safariHome)
        #expect(rig.record == nil)
        #expect(rig.desk.state.placed == nil)
        #expect(rig.desk.state.listVisible)
    }

    @Test("放的过程讲得清：先是「正在放」（带着是哪个窗口），挪好转成调字号，做完回到空闲")
    func workDuringPull() async throws {
        let rig = try Rig()
        await rig.ready()
        var works: [PhoneDesk.Work?] = []
        rig.desk.onChange = { state in
            if works.last != .some(state.work) { works.append(state.work) }
        }
        await rig.pull(ghostty)
        #expect(works == [.placing(ghostty), .zooming, nil])
    }

    @Test("还原时 App 卡住：窗口留在手机屏上照旧算放着（字号按缩回了的算），提示无响应、记录留着；好了再点能放回")
    func putBackStuck() async throws {
        let rig = try Rig()
        await rig.ready()
        await rig.pull(ghostty)
        rig.desk.showList()
        rig.windows.blockMoves()
        rig.desk.putBack()
        await rig.desk.idle()
        #expect(rig.desk.state.placed == PhoneDesk.Placed(window: ghostty, zoom: 0))
        #expect(rig.desk.state.notice == .windowUnresponsive(app: "Ghostty"))
        #expect(rig.desk.state.listVisible)
        #expect(rig.record?.zoom == 0)

        rig.windows.blockMoves(false)
        rig.journal.clear()
        rig.desk.putBack()
        await rig.desk.idle()
        #expect(rig.journal.all == ["move 7 \(ghosttyHome.short) ✎"])   // 字号已经缩回过，不再缩
        #expect(rig.windows.window(ghostty.key)?.zoom == 0)
        #expect(rig.desk.state.placed == nil)
        #expect(rig.record == nil)
    }

    @Test("换窗口时原来那个放不回去：不换（两个会叠在手机屏上，记录也只记得住一个），提示原来那个无响应")
    func switchBlockedByStuckWindow() async throws {
        let rig = try Rig()
        await rig.ready()
        await rig.pull(ghostty)
        rig.windows.blockMoves()
        await rig.pull(finder)
        #expect(rig.desk.state.placed?.window == ghostty)
        #expect(rig.desk.state.notice == .windowUnresponsive(app: "Ghostty"))
        #expect(rig.record?.window == ghostty.key)
        #expect(rig.windows.window(finder.key)?.frame == finderHome)
        #expect(rig.desk.state.work == nil)
    }

    @Test("上次远程没放回去的窗口（App 卡住）：下次放别的窗口前先把它放回原位、缩回字号，记录不被新的盖掉")
    func leftoverPutBackBeforeNextPlace() async throws {
        let rig = try Rig()
        await rig.ready()
        await rig.pull(ghostty)
        rig.windows.block()
        rig.timeline.advance(10)
        rig.desk.setWanted(false)
        await rig.desk.idle()
        #expect(rig.record?.window == ghostty.key)
        let elsewhere = CGRect(x: 50, y: 60, width: 540, height: 897)
        rig.windows.setFrame(ghostty.key, elsewhere)          // 撤屏后系统把它挪到了主屏

        rig.windows.block(false)
        await rig.ready()
        await rig.pull(finder)
        #expect(rig.journal.all.prefix(2) == ["zoom 7 -2 ✎", "move 7 \(ghosttyHome.short) ✎"])
        #expect(rig.windows.window(ghostty.key)?.frame == ghosttyHome)
        #expect(rig.windows.window(ghostty.key)?.zoom == 0)
        #expect(rig.record?.window == finder.key)
        #expect(rig.desk.state.placed?.window == finder)
    }

    @Test("上次没放回去的窗口还是卡着：先不放新的，提示是哪个 App，记录还是它的")
    func leftoverStillStuck() async throws {
        let rig = try Rig()
        await rig.ready()
        await rig.pull(ghostty)
        rig.windows.blockMoves()
        rig.timeline.advance(10)
        rig.desk.setWanted(false)
        await rig.desk.idle()
        await rig.ready()
        await rig.pull(finder)
        #expect(rig.desk.state.placed == nil)
        #expect(rig.desk.state.notice == .windowUnresponsive(app: "Ghostty"))
        #expect(rig.record?.window == ghostty.key)
        #expect(rig.windows.window(finder.key)?.frame == finderHome)
    }

    @Test("还原时字号按键发不出去：先不挪（挪回就销账了，多出来的字号再没人缩），照旧放着、提示无响应")
    func putBackZoomFails() async throws {
        let rig = try Rig()
        await rig.ready()
        await rig.pull(ghostty)
        rig.windows.blockZoom()
        rig.journal.clear()
        rig.desk.putBack()
        await rig.desk.idle()
        #expect(rig.journal.all.isEmpty)
        #expect(rig.desk.state.placed == PhoneDesk.Placed(window: ghostty, zoom: 2))
        #expect(rig.desk.state.notice == .windowUnresponsive(app: "Ghostty"))
        #expect(rig.record?.zoom == 2)
    }

    @Test("放着一个窗口时点到刚关掉的卡片：现在这个不动，提示那个已关闭")
    func pullClosedWhilePlaced() async throws {
        let rig = try Rig()
        await rig.ready()
        await rig.pull(ghostty)
        rig.windows.close(finder.key)
        rig.journal.clear()
        await rig.pull(finder)
        #expect(rig.journal.all.isEmpty)
        #expect(rig.desk.state.placed == PhoneDesk.Placed(window: ghostty, zoom: 2))
        #expect(rig.desk.state.notice == .windowGone(app: "Finder"))
    }

    @Test("列表收着时出的错（放上来后调字号没成）：点小横条回到列表还看得到；点返回键才清掉")
    func noticeSurvivesShowList() async throws {
        let rig = try Rig()
        await rig.ready()
        rig.windows.blockZoom()
        await rig.pull(ghostty)
        #expect(rig.desk.state.listVisible == false)
        #expect(rig.desk.state.notice == .windowUnresponsive(app: "Ghostty"))
        rig.desk.showList()
        #expect(rig.desk.state.notice == .windowUnresponsive(app: "Ghostty"))
        rig.desk.returnToPlaced()
        #expect(rig.desk.state.notice == nil)
    }

    @Test("这次远程的提示不带到下一次")
    func noticeClearedWithScreen() async throws {
        let rig = try Rig()
        await rig.ready()
        rig.windows.close(finder.key)
        await rig.pull(finder)
        #expect(rig.desk.state.notice != nil)
        rig.timeline.advance(10)
        rig.desk.setWanted(false)
        await rig.desk.idle()
        await rig.ready()
        #expect(rig.desk.state.notice == nil)
    }

    @Test("字号到了上限再点放大：什么都不做，也不闪「忙」")
    func zoomAtLimitDoesNothing() async throws {
        let rig = try Rig()
        await rig.ready()
        await rig.pull(ghostty)
        rig.desk.zoom(by: ZoomBook.range.upperBound - 2)
        await rig.desk.idle()
        #expect(rig.desk.state.placed?.zoom == ZoomBook.range.upperBound)
        rig.journal.clear()
        var works: [PhoneDesk.Work?] = []
        rig.desk.onChange = { works.append($0.work) }
        rig.desk.zoom(by: 1)
        await rig.desk.idle()
        #expect(rig.journal.all.isEmpty)
        #expect(works.isEmpty)
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

    @Test("建好不到 2.5 秒就要撤：先等够再撤（太早释放会让 WindowServer 卡死）")
    func minimumLifetime() async throws {
        let rig = try Rig()
        await rig.ready()
        rig.desk.setWanted(false)
        await rig.desk.idle()
        let created = try #require(rig.displays.createdAt[101])
        let retired = try #require(rig.displays.retiredAt[101])
        #expect(retired - created >= PhoneScreenSpec.minimumLifetime)
    }

    @Test("不要手机屏了（会话结束）：窗口放回原位、字号缩回，再撤屏；记录销账")
    func teardown() async throws {
        let rig = try Rig()
        await rig.ready()
        await rig.pull(ghostty)
        rig.journal.clear()
        rig.timeline.advance(10)
        rig.desk.setWanted(false)
        await rig.desk.idle()
        #expect(rig.journal.all == [
            "zoom 7 -2 ✎", "move 7 \(ghosttyHome.short) ✎",
            "snapshot", "retire 101", "restore",
        ])
        #expect(rig.windows.window(ghostty.key)?.frame == ghosttyHome)
        #expect(rig.record == nil)
        #expect(rig.desk.state.screen == .off)
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
        rig.desk.setDefaultZoom(0)
        await rig.ready()
        await rig.pull(ghostty)
        #expect(!rig.journal.all.contains { $0.hasPrefix("zoom") })
    }

    @Test("还原记录写不进去：什么都不动（全屏的也不退出），告诉用户")
    func ledgerFailureBlocksChange() async throws {
        let blocker = FileManager.default.temporaryDirectory.appendingPathComponent("snug-blocker-\(UUID().uuidString)")
        try Data().write(to: blocker)
        defer { try? FileManager.default.removeItem(at: blocker) }
        // 数据目录的位置是个普通文件，记录写不进去
        let rig = try Rig(dataDirectory: blocker.appendingPathComponent("data"))
        await rig.ready()
        await rig.pull(safari)
        #expect(rig.journal.all.isEmpty)
        #expect(rig.windows.window(safari.key)?.fullScreen == true)
        #expect(rig.desk.state.placed == nil)
        #expect(rig.desk.state.notice == .recordUnwritable)
        #expect(rig.desk.state.listVisible)
    }

    @Test("要放的窗口已经关了：告诉用户，什么都不动")
    func pullClosedWindow() async throws {
        let rig = try Rig()
        await rig.ready()
        rig.windows.close(finder.key)
        await rig.pull(finder)
        #expect(rig.desk.state.notice == .windowGone(app: "Finder"))
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

    @Test("手机屏上的窗口还在却不在屏上（飞书点关闭只是藏起来）：回到列表，照旧算放着、记录留着")
    func placedWindowHidden() async throws {
        let rig = try Rig()
        await rig.ready()
        await rig.pull(finder)
        rig.windows.hide(finder.key)
        rig.desk.verifyPlacement()
        await rig.desk.idle()
        #expect(rig.desk.state.listVisible)
        #expect(rig.desk.state.placed?.window == finder)
        #expect(rig.record?.window == finder.key)
    }

    @Test("App 没响应（或权限被收回）：核对时不当成已关；放不回去的窗口记录留着，恢复时也不动")
    func unresponsiveApp() async throws {
        let rig = try Rig()
        await rig.ready()
        await rig.pull(ghostty)
        rig.windows.block()
        rig.desk.verifyPlacement()
        await rig.desk.idle()
        #expect(rig.desk.state.placed != nil)   // 读不到不等于关了：窗口服务器说它还在
        rig.timeline.advance(10)
        rig.desk.setWanted(false)
        await rig.desk.idle()
        #expect(rig.record == PhoneRecord(window: ghostty.key, app: ghostty.app, label: ghostty.label, original: ghosttyHome, zoom: 2))
        rig.desk.recover()
        await rig.desk.idle()
        #expect(rig.record != nil)
    }

    @Test("要放的窗口读不到但还在：提示无响应，什么都不动")
    func pullUnresponsiveWindow() async throws {
        let rig = try Rig()
        await rig.ready()
        rig.windows.block()
        await rig.pull(finder)
        #expect(rig.desk.state.notice == .windowUnresponsive(app: "Finder"))
        #expect(rig.record == nil)
        #expect(rig.journal.all.isEmpty)
    }

    @Test("原来最小化的窗口：先记账再还原，放回时再最小化")
    func minimizedWindow() async throws {
        let rig = try Rig()
        await rig.ready()
        await rig.pull(notes)
        #expect(rig.journal.all == ["minimize 10 off ✎", "move 10 \(phoneArea.short) ✎", "focus 10"])
        #expect(rig.record?.wasMinimized == true)
        rig.journal.clear()
        rig.desk.putBack()
        await rig.desk.idle()
        #expect(rig.journal.all == ["move 10 \(notesHome.short) ✎", "minimize 10 on ✎"])
        #expect(rig.record == nil)
    }

    @Test("放回时字号缩完马上记账：挪窗口那一刻记录里已经是 0 级（中途崩溃不会再缩一遍）")
    func zoomRevertRecordedFirst() async throws {
        let rig = try Rig()
        await rig.ready()
        await rig.pull(ghostty)
        let seen = Locked<[Int]>([])
        let ledger = rig.paths.phoneRecord
        rig.windows.onMove { _ in
            if let zoom = RestoreRecord<PhoneRecord>(url: ledger).pending()?.zoom { seen.withLock { $0.append(zoom) } }
        }
        rig.desk.putBack()
        await rig.desk.idle()
        #expect(seen.withLock { $0 } == [0])
        #expect(rig.record == nil)
    }

    @Test("调字号后窗口被撑大（终端保持行列数）：重新铺满手机屏")
    func refillAfterZoom() async throws {
        let rig = try Rig()
        rig.windows.growOnZoom()
        await rig.ready()
        await rig.pull(ghostty)
        #expect(rig.journal.all == [
            "move 7 \(phoneArea.short) ✎", "focus 7", "zoom 7 +2 ✎", "move 7 \(phoneArea.short) ✎",
        ])
        #expect(rig.windows.window(ghostty.key)?.frame == phoneArea)
    }

    @Test("字号按键没发出去：记录改回原来的级数（不然还原时多缩），提示无响应")
    func zoomFailureKeepsRecordHonest() async throws {
        let rig = try Rig()
        await rig.ready()
        await rig.pull(ghostty)
        rig.windows.block()
        rig.desk.zoom(by: 1)
        await rig.desk.idle()
        #expect(rig.record?.zoom == 2)
        #expect(rig.desk.state.placed?.zoom == 2)
        #expect(rig.desk.state.notice == .windowUnresponsive(app: "Ghostty"))
    }

    @Test("手机屏的可放区域读不到：不放，提示手机屏未就绪")
    func pullWhenScreenNotReady() async throws {
        let rig = try Rig()
        await rig.ready()
        rig.displays.area = nil
        await rig.pull(finder)
        #expect(rig.desk.state.notice == .screenNotReady)
        #expect(rig.journal.all.isEmpty)
        #expect(rig.desk.state.work == nil)
    }

    @Test("撤屏：原本就在手机屏上的窗口（手机上新开的）交给系统安置，不放回已经没了的屏")
    func retireLeavesPhoneWindowsToSystem() async throws {
        let rig = try Rig()
        await rig.ready()
        rig.windows.setFrame(finder.key, phoneArea)          // 手机上新开的窗口
        let mainSpot = CGRect(x: 100, y: 100, width: 540, height: 897)
        rig.displays.onRetire = {
            rig.windows.setFrame(finder.key, mainSpot)       // 系统把它挪到主屏
            rig.windows.setFrame(ghostty.key, phoneArea)     // 别的窗口被系统挪乱
        }
        rig.timeline.advance(10)
        rig.desk.setWanted(false)
        await rig.desk.idle()
        #expect(rig.windows.window(finder.key)?.frame == mainSpot)
        #expect(rig.windows.window(ghostty.key)?.frame == ghosttyHome)
    }

    @Test("加屏一直失败：按 5、15、30 秒重试三次后不再试，显示失败；不要了就回到关闭")
    func createFails() async throws {
        let rig = try Rig()
        rig.displays.failuresLeft = .max
        rig.desk.setWanted(true)
        await rig.desk.idle()
        #expect(rig.journal.all.filter { $0.hasPrefix("create") }.count == 4)
        #expect(rig.desk.state.screen == .failed)
        rig.desk.setWanted(false)
        await rig.desk.idle()
        #expect(rig.desk.state.screen == .off)
        #expect(!rig.journal.all.contains { $0.hasPrefix("retire") })
    }

    @Test("加屏失败一次：过一会儿重试，加上了")
    func retryAfterFailure() async throws {
        let rig = try Rig()
        rig.displays.failuresLeft = 1
        rig.desk.setWanted(true)
        await rig.desk.idle()
        #expect(rig.journal.all.filter { $0.hasPrefix("create") }.count == 2)
        #expect(rig.desk.state.screen == .ready(101))
    }

    @Test("设置里改默认级数：各 App 记住的级数清掉，以新的为准")
    func defaultZoomResetsMemory() async throws {
        let rig = try Rig()
        await rig.ready()
        await rig.pull(ghostty)
        rig.desk.zoom(by: 1)
        await rig.desk.idle()
        rig.desk.setDefaultZoom(1)
        await rig.pull(finder)
        rig.journal.clear()
        await rig.pull(ghostty)
        #expect(rig.journal.all.last == "zoom 7 +1 ✎")
    }

    @Test("App 限定了最小宽度（系统设置、Safari）：靠左放；之后核对不再白挪，被挪动了才重新铺满")
    func minimumWidthWindow() async throws {
        let rig = try Rig()
        rig.windows.setMinWidth(finder.key, 740)
        await rig.ready()
        await rig.pull(finder)
        let clamped = CGRect(x: phoneArea.minX, y: phoneArea.minY, width: 740, height: phoneArea.height)
        #expect(rig.windows.window(finder.key)?.frame == clamped)
        rig.journal.clear()
        rig.desk.displaysChanged()
        await rig.desk.idle()
        #expect(rig.journal.all == ["ensure 101"])      // 铺不满是 App 定的，不再挪
        rig.windows.setFrame(finder.key, CGRect(x: 0, y: 25, width: 740, height: 500))
        rig.journal.clear()
        rig.desk.displaysChanged()
        await rig.desk.idle()
        #expect(rig.journal.all == ["ensure 101", "move 8 \(phoneArea.short) ✎"])
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
            PhoneRecord(window: safari.key, app: safari.app, label: safari.label, original: safariHome, wasFullScreen: true, zoom: 2))
        rig.desk.recover()
        rig.desk.recover()   // 连着两次：第二次轮到时记录已经销了，不会再放一遍
        await rig.desk.idle()
        #expect(rig.journal.all == ["zoom 9 -2 ✎", "move 9 \(safariHome.short) ✎", "fullscreen 9 on ✎"])
        #expect(rig.record == nil)
    }

    @Test("上次崩溃留下的记录，窗口已经不在了：记录作废，什么都不动")
    func recoverGoneWindow() async throws {
        let rig = try Rig()
        rig.windows.close(safari.key)
        try RestoreRecord<PhoneRecord>(url: rig.paths.phoneRecord).record(
            PhoneRecord(window: safari.key, app: safari.app, label: safari.label, original: safariHome, wasFullScreen: true, zoom: 2))
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
