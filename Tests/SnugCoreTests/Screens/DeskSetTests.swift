import CoreGraphics
import Foundation
import Testing
@testable import SnugCore

/// 第二块屏：新加的屏的身份
private let second = ScreenID("second")
private let secondSpec = ScreenSpec(name: "Snug 第二块", productID: ScreenSpec.portraitProductID,
                                    serials: [200_100_000, 200_100_001, 200_100_002], maxPixels: ScreenFit.portraitPixels)
private let computer = ScreenBehavior.computer

@MainActor
private extension Rig {
    func secondWish(_ behavior: ScreenBehavior = .touchScreen) -> ScreenWish {
        ScreenWish(id: second, spec: secondSpec, fit: .standard, behavior: behavior)
    }

    /// 两块屏都建好，流水账清空
    func readyTwo(_ behavior: ScreenBehavior = .touchScreen) async {
        set.setWishes([desk.wish, secondWish(behavior)])
        await set.idle()
        journal.clear()
    }

    func placed(on id: ScreenID) -> WindowInfo? { set.state.desks[id]?.placed?.window }
    func record(of id: ScreenID) -> PlacedRecord? { RestoreRecord<PlacedRecord>(url: paths.placedRecord(for: id)).pending() }
    /// 电脑屏上挪过来的这个窗口的那份账
    func brought(_ w: WindowInfo, on id: ScreenID) -> PlacedRecord? {
        RestoreRecord<PlacedRecord>(url: paths.broughtRecord(for: id, window: w.key)).pending()
    }
    /// 电脑屏上挪过来、能还原的窗口
    func broughtKeys(on id: ScreenID) -> Set<WindowKey>? { set.state.desks[id]?.brought }
    /// 电脑屏的可放区域里居中（挪过来的样子）
    func centeredOnSecond(_ size: CGSize) throws -> CGRect {
        try #require(displays.windowArea(102, withHomeBar: false)).centered(size)
    }
    /// 第二块屏的可放区域（假屏往右排，第二块在第一块右边 4000 点）
    var secondArea: CGRect { phoneArea.offsetBy(dx: 4000, dy: 0) }
}

@Suite("多块屏 DeskSet")
@MainActor
struct DeskSetTests {
    @Test("两块屏一批建：前后只拍一次快照、只善后一次；各用各的身份")
    func createsTogether() async throws {
        let rig = try Rig()
        rig.set.setWishes([rig.desk.wish, rig.secondWish()])
        await rig.set.idle()
        #expect(rig.journal.all == ["snapshot", "create", "create", "restore"])
        #expect(rig.set.state.desks[.phone]?.screen == .ready(101))
        #expect(rig.set.state.desks[second]?.screen == .ready(102))
        #expect(rig.displays.specs[101]?.name == "Snug 手机屏")
        #expect(rig.displays.specs[102]?.name == "Snug 第二块")
    }

    @Test("每块屏各放各的，互不打扰；还原账每块一份")
    func independent() async throws {
        let rig = try Rig()
        await rig.readyTwo()
        await rig.pull(ghostty)
        rig.set.pull(finder, on: second)
        await rig.set.idle()
        #expect(rig.placed(on: .phone) == ghostty)
        #expect(rig.placed(on: second) == finder)
        #expect(rig.windows.window(ghostty.key)?.frame == phoneArea)
        #expect(rig.windows.window(finder.key)?.frame == rig.secondArea)
        #expect(rig.record(of: .phone)?.original == ghosttyHome)
        #expect(rig.record(of: second)?.original == finderHome)
    }

    @Test("在 B 屏上点已经放在 A 屏上的窗口：挪到 B，A 回到 App 资源库；原位记录跟着走，中间不还原一次")
    func transfer() async throws {
        let rig = try Rig()
        await rig.readyTwo()
        await rig.pull(ghostty)
        rig.journal.clear()
        rig.set.pull(ghostty, on: second)
        await rig.set.idle()
        #expect(rig.placed(on: .phone) == nil)
        #expect(rig.set.state.desks[.phone]?.listVisible == true)
        #expect(rig.placed(on: second) == ghostty)
        #expect(rig.windows.window(ghostty.key)?.frame == rig.secondArea)
        #expect(!rig.journal.all.contains("move 7 \(ghosttyHome.short)"))
        #expect(!rig.journal.all.contains { $0.hasPrefix("zoom") })
        #expect(rig.record(of: .phone) == nil)
        #expect(rig.record(of: second)?.original == ghosttyHome)
        // 再从 B 放回原位：回到最初的位置，字号缩回
        rig.set.putBack(on: second)
        await rig.set.idle()
        #expect(rig.windows.window(ghostty.key)?.frame == ghosttyHome)
        #expect(rig.windows.window(ghostty.key)?.zoom == 0)
    }

    @Test("转过去时 B 屏原来那个窗口放不回去（App 卡住）：不转，窗口留在 A 屏上，A 照旧认它、账照旧")
    func transferBlockedByStuckTarget() async throws {
        let rig = try Rig()
        await rig.readyTwo()
        await rig.pull(ghostty)
        rig.set.pull(finder, on: second)
        await rig.set.idle()
        let before = rig.record(of: .phone)
        rig.windows.refuseMoves { key, _ in key == finder.key }
        rig.set.pull(ghostty, on: second)
        await rig.set.idle()
        #expect(rig.placed(on: .phone) == ghostty)
        #expect(rig.set.state.desks[.phone]?.listVisible == false)
        #expect(rig.windows.window(ghostty.key)?.frame == phoneArea)
        #expect(rig.record(of: .phone) == before)
        #expect(rig.set.state.desks[second]?.notice == .windowUnresponsive(app: finder.app))
    }

    @Test("转过去时铺到 B 屏那一下挪不动：B 按跟过来的账放回原位，A 的那份一起销，之后不再还一遍")
    func transferFillFails() async throws {
        let rig = try Rig()
        await rig.readyTwo()
        await rig.pull(ghostty)
        let area = rig.secondArea
        rig.windows.refuseMoves { key, frame in key == ghostty.key && frame == area }
        rig.set.pull(ghostty, on: second)
        await rig.set.idle()
        #expect(rig.windows.window(ghostty.key)?.frame == ghosttyHome)
        #expect(rig.windows.window(ghostty.key)?.zoom == 0)
        #expect(rig.placed(on: .phone) == nil)
        #expect(rig.placed(on: second) == nil)
        #expect(rig.record(of: .phone) == nil)
        #expect(rig.record(of: second) == nil)
        await rig.pull(finder)
        #expect(rig.windows.window(ghostty.key)?.zoom == 0)
        #expect(rig.windows.window(ghostty.key)?.frame == ghosttyHome)
    }

    @Test("挪到电脑屏：先在手机屏上放回原位、缩回字号，再挪到电脑屏居中，不铺满")
    func transferToComputer() async throws {
        let rig = try Rig()
        await rig.readyTwo(computer)
        await rig.pull(ghostty)
        rig.set.pull(ghostty, on: second)
        await rig.set.idle()
        #expect(rig.placed(on: .phone) == nil)
        #expect(rig.windows.window(ghostty.key)?.zoom == 0)
        let area = try #require(rig.displays.windowArea(102, withHomeBar: false))
        #expect(rig.windows.window(ghostty.key)?.frame == area.centered(ghosttyHome.size))
        #expect(rig.record(of: .phone) == nil)
        #expect(rig.record(of: second) == nil)
    }

    @Test("撤一块屏，另一块不动：撤的那块按账放回，留下的那块照旧放着")
    func removeOne() async throws {
        let rig = try Rig()
        await rig.readyTwo()
        await rig.pull(ghostty)
        rig.set.pull(finder, on: second)
        await rig.set.idle()
        rig.timeline.advance(10)
        rig.journal.clear()
        rig.set.setWishes([rig.desk.wish])
        await rig.set.idle()
        #expect(rig.journal.all.contains("retire 102"))
        #expect(!rig.journal.all.contains("retire 101"))
        #expect(rig.windows.window(finder.key)?.frame == finderHome)
        #expect(rig.placed(on: .phone) == ghostty)
        #expect(rig.windows.window(ghostty.key)?.frame == phoneArea)
        #expect(rig.set.state.desks[second] == nil)
        #expect(rig.record(of: second) == nil)
    }

    @Test("撤屏前清场：用户在这块屏上直接开的窗口挪到主屏居中，大小不超过主屏；最小化的、别的屏上的不动")
    func clearsBeforeRetire() async throws {
        let rig = try Rig()
        await rig.readyTwo(computer)
        let memo = WindowInfo(key: WindowKey(pid: 30, id: 40), app: "备忘录", bundleID: "com.apple.Notes", title: "新开的")
        let huge = WindowInfo(key: WindowKey(pid: 31, id: 41), app: "预览", bundleID: "com.apple.Preview", title: "大图")
        let memoFrame = CGRect(x: rig.secondArea.minX + 50, y: 100, width: 600, height: 400)
        rig.windows.add(memo.key, frame: memoFrame, info: memo)
        rig.windows.add(huge.key, frame: CGRect(x: rig.secondArea.midX - 1500, y: 0, width: 3000, height: 1000), info: huge)
        rig.timeline.advance(10)
        rig.set.setWishes([rig.desk.wish])
        await rig.set.idle()
        let main = FakeDisplays.main
        #expect(rig.windows.window(memo.key)?.frame == main.centered(memoFrame.size))
        #expect(rig.windows.window(huge.key)?.frame == main)
        #expect(rig.windows.window(ghostty.key)?.frame == ghosttyHome)
        // 清场在撤屏之前（∅：这块屏没记账），挪完的位置记进撤屏前的快照，善后不会把它们挪回去
        #expect(rig.journal.all == ["move 40 \(main.centered(memoFrame.size).short) ∅", "move 41 \(main.short) ∅", "snapshot", "retire 102", "restore"])
    }

    @Test("退出 App：它在各块屏上的窗口都先放回原位")
    func quitAcrossScreens() async throws {
        let rig = try Rig()
        let second7 = WindowInfo(key: WindowKey(pid: ghostty.key.pid, id: 70), app: ghostty.app, bundleID: ghostty.bundleID, title: "~/other")
        let secondHome = CGRect(x: 200, y: 150, width: 900, height: 600)
        rig.windows.add(second7.key, frame: secondHome, info: second7)
        await rig.readyTwo()
        await rig.pull(ghostty)
        rig.set.pull(second7, on: second)
        await rig.set.idle()
        rig.set.quit(RunningApp(pid: ghostty.key.pid, app: AppInfo(bundleID: "com.mitchellh.ghostty", name: ghostty.app, path: nil), windows: [ghostty, second7]), from: .phone)
        await rig.set.idle()
        #expect(rig.windows.window(ghostty.key)?.frame == ghosttyHome)
        #expect(rig.windows.window(second7.key)?.frame == secondHome)
        #expect(rig.placed(on: .phone) == nil)
        #expect(rig.placed(on: second) == nil)
    }

    @Test("在手机上退出一块屏：只退这一块，这次远程不再加它；另一块照旧")
    func dismissOne() async throws {
        let rig = try Rig()
        await rig.readyTwo()
        await rig.pull(ghostty)
        rig.timeline.advance(10)
        rig.set.dismissScreen(second)
        await rig.set.idle()
        #expect(rig.set.state.desks[second] == nil)
        #expect(rig.set.state.dismissed == [second])
        #expect(rig.placed(on: .phone) == ghostty)
        // 同一次远程里再算一遍要哪些屏：退出的那块不回来
        rig.set.setWishes([rig.desk.wish, rig.secondWish()])
        await rig.set.idle()
        #expect(rig.set.state.desks[second] == nil)
        // 远程结束再开始：回来
        rig.set.setWishes([])
        await rig.set.idle()
        rig.set.setWishes([rig.desk.wish, rig.secondWish()])
        await rig.set.idle()
        #expect(rig.set.state.desks[second]?.screen.display != nil)
    }

    @Test("启动时按每块屏的账还原：上次崩溃时两块屏上各放着一个窗口")
    func recoverAll() async throws {
        let tmp = try TempDir()
        do {
            let rig = try Rig(dataDirectory: tmp.url)
            await rig.readyTwo()
            await rig.pull(ghostty)
            rig.set.pull(finder, on: second)
            await rig.set.idle()
        }
        let rig = try Rig(dataDirectory: tmp.url)
        rig.windows.setFrame(ghostty.key, phoneArea)
        rig.windows.setFrame(finder.key, phoneArea.offsetBy(dx: 4000, dy: 0))
        rig.set.recover()
        await rig.set.idle()
        #expect(rig.windows.window(ghostty.key)?.frame == ghosttyHome)
        #expect(rig.windows.window(finder.key)?.frame == finderHome)
        #expect(rig.record(of: .phone) == nil)
        #expect(rig.record(of: second) == nil)
    }

    @Test("2.5 留下的还原账 phone-screen.json：挪成 placed/phone.json 再按它还原")
    func migratesLegacyRecord() async throws {
        let rig = try Rig()
        let record = PlacedRecord(window: ghostty.key, app: ghostty.app, label: ghostty.label, original: ghosttyHome, wasFullScreen: false, zoom: 2,
                                  bundleID: ghostty.bundleID, title: ghostty.title, filled: phoneArea)
        try RestoreRecord<PlacedRecord>(url: rig.paths.legacyPlacedRecord).record(record)
        rig.windows.setFrame(ghostty.key, phoneArea)
        rig.set.recover()
        await rig.set.idle()
        #expect(rig.windows.window(ghostty.key)?.frame == ghosttyHome)
        #expect(!FileManager.default.fileExists(atPath: rig.paths.legacyPlacedRecord.path))
        #expect(rig.record(of: .phone) == nil)
    }

    @Test("2.5 的 phone-screen.json 和 placed/phone.json 都在（新版留了账、降级回 2.5 又崩了一次）：两笔账都还，一笔不丢")
    func migratesLegacyRecordBesideNewOne() async throws {
        let rig = try Rig()
        let stuck = PlacedRecord(window: finder.key, app: finder.app, label: finder.label, original: finderHome,
                                 bundleID: finder.bundleID, title: finder.title, filled: phoneArea)
        let crashed = PlacedRecord(window: ghostty.key, app: ghostty.app, label: ghostty.label, original: ghosttyHome, zoom: 2,
                                   bundleID: ghostty.bundleID, title: ghostty.title, filled: phoneArea)
        try RestoreRecord<PlacedRecord>(url: rig.paths.placedRecord(for: .phone)).record(stuck)
        try RestoreRecord<PlacedRecord>(url: rig.paths.legacyPlacedRecord).record(crashed)
        rig.windows.setFrame(finder.key, phoneArea)
        rig.windows.setFrame(ghostty.key, phoneArea)
        rig.set.recover()
        await rig.set.idle()
        #expect(rig.windows.window(finder.key)?.frame == finderHome)
        #expect(rig.windows.window(ghostty.key)?.frame == ghosttyHome)
        #expect(rig.windows.window(ghostty.key)?.zoom == -2)
        #expect(!FileManager.default.fileExists(atPath: rig.paths.legacyPlacedRecord.path))
        #expect((try? FileManager.default.contentsOfDirectory(atPath: rig.paths.placedRecords.path))?.isEmpty != false)
    }

    @Test("加屏失败、等着重试时改了别的设置（又走一次差量）：不当场再建失败的那块，三次重试照样按点来")
    func failedWaitsForRetry() async throws {
        let rig = try Rig()
        rig.set.setWishes([rig.desk.wish])
        await rig.set.idle()
        rig.journal.clear()
        rig.displays.failuresLeft = .max
        rig.set.setWishes([rig.desk.wish, rig.secondWish()])
        var renamed = rig.secondWish()
        renamed.behavior = computer
        rig.set.setWishes([rig.desk.wish, renamed])
        await rig.set.idle()
        // 头一次加三次重试，一共 4 次
        #expect(rig.journal.all.filter { $0.hasPrefix("create") }.count == 4)
        #expect(rig.set.state.desks[second]?.screen == .failed)
    }

    @Test("加屏时 macOS 把留着的 Snug 屏也挪开了：那块屏上的窗口按它挪过的距离放回，不推回旧坐标")
    func followsNudgedSnugScreen() async throws {
        let rig = try Rig()
        let computerWish = ScreenWish(id: rig.desk.wish.id, spec: rig.desk.wish.spec, fit: .standard, behavior: computer)
        rig.set.setWishes([computerWish])
        await rig.set.idle()
        let screen = try #require(rig.displays.bounds(101))
        let safari = WindowInfo(key: WindowKey(pid: 31, id: 51), app: "Safari", bundleID: "com.apple.Safari", title: "Snug")
        let frame = CGRect(x: screen.minX + 20, y: screen.minY + 40, width: 300, height: 200)
        rig.windows.add(safari.key, frame: frame, info: safari)
        rig.displays.onCreate = { [displays = rig.displays, windows = rig.windows] in
            displays.nudged[101] = CGVector(dx: 1180, dy: 0)
            windows.setFrame(safari.key, FakeDisplays.main)      // 系统挪屏时把窗口挪乱了
        }
        rig.set.setWishes([computerWish, rig.secondWish()])
        await rig.set.idle()
        #expect(rig.windows.window(safari.key)?.frame == frame.offsetBy(dx: 1180, dy: 0))
    }

    @Test("显示器睡着时先后撤了两块屏（都还没下线）：等两块都下线了再放回窗口，不在先下线的那块之后就收工")
    func twoRetiresWhileAsleep() async throws {
        let rig = try Rig()
        await rig.readyTwo()
        rig.timeline.advance(10)
        let memo = WindowInfo(key: WindowKey(pid: 32, id: 52), app: "备忘录", bundleID: "com.apple.Notes", title: "清单")
        let home = CGRect(x: 200, y: 200, width: 500, height: 400)
        rig.windows.add(memo.key, frame: home, info: memo)
        rig.displays.staysOnline = true
        rig.set.setWishes([rig.desk.wish])
        await rig.set.idle()
        rig.set.setWishes([])
        await rig.set.idle()
        rig.displays.goOffline(101)
        rig.set.settleDisplays()
        await rig.set.idle()
        // 后下线的那块下线时系统又把窗口挪乱了
        rig.displays.onRetire = { [windows = rig.windows] in windows.setFrame(memo.key, FakeDisplays.main) }
        rig.displays.goOffline(102)
        rig.set.settleDisplays()
        await rig.set.idle()
        #expect(rig.windows.window(memo.key)?.frame == home)
    }

    // MARK: 电脑屏的还原

    @Test("挪到电脑屏：先记账（一个窗口一份），资源库里还原就放回原处、销掉这一份；别的照旧在屏上")
    func bringRecordsAndPutsBack() async throws {
        let rig = try Rig()
        await rig.readyTwo(computer)
        rig.set.pull(ghostty, on: second)
        rig.set.pull(finder, on: second)
        await rig.set.idle()
        #expect(rig.windows.window(ghostty.key)?.frame == (try rig.centeredOnSecond(ghosttyHome.size)))
        #expect(rig.brought(ghostty, on: second)?.original == ghosttyHome)
        #expect(rig.brought(finder, on: second)?.original == finderHome)
        #expect(rig.broughtKeys(on: second) == [ghostty.key, finder.key])
        rig.set.putBack(ghostty.key, on: second)
        await rig.set.idle()
        #expect(rig.windows.window(ghostty.key)?.frame == ghosttyHome)
        #expect(rig.brought(ghostty, on: second) == nil)
        #expect(rig.broughtKeys(on: second) == [finder.key])
        #expect(rig.windows.window(finder.key)?.frame == (try rig.centeredOnSecond(finderHome.size)))
    }

    @Test("撤电脑屏：挪过来的窗口按账放回原处（不挪到主屏正中），账销掉")
    func retireComputerPutsBroughtBack() async throws {
        let rig = try Rig()
        await rig.readyTwo(computer)
        rig.set.pull(ghostty, on: second)
        rig.set.pull(finder, on: second)
        await rig.set.idle()
        rig.timeline.advance(10)
        rig.set.setWishes([rig.desk.wish])
        await rig.set.idle()
        #expect(rig.windows.window(ghostty.key)?.frame == ghosttyHome)
        #expect(rig.windows.window(finder.key)?.frame == finderHome)
        #expect(rig.brought(ghostty, on: second) == nil)
        #expect(rig.brought(finder, on: second) == nil)
    }

    @Test("原来全屏的窗口挪到电脑屏：原位按退出全屏后的位置记，还原时恢复全屏")
    func bringFullScreenRestoresIt() async throws {
        let rig = try Rig()
        await rig.readyTwo(computer)
        rig.set.pull(safari, on: second)
        await rig.set.idle()
        let record = try #require(rig.brought(safari, on: second))
        #expect(record.original == safariWindowed)
        #expect(record.wasFullScreen)
        rig.set.putBack(safari.key, on: second)
        await rig.set.idle()
        #expect(rig.windows.window(safari.key)?.fullScreen == true)
        #expect(rig.brought(safari, on: second) == nil)
    }

    @Test("挪过来的窗口被用户挪去了别的屏：定期核对时销账，撤屏时不拽回来")
    func movedAwayIsLeftAlone() async throws {
        let rig = try Rig()
        await rig.readyTwo(computer)
        rig.set.pull(ghostty, on: second)
        await rig.set.idle()
        let moved = CGRect(x: FakeDisplays.main.minX + 40, y: FakeDisplays.main.minY + 40, width: 800, height: 600)
        rig.windows.setFrame(ghostty.key, moved)
        rig.set.verifyPlacement()
        await rig.set.idle()
        rig.timeline.advance(10)
        rig.set.setWishes([rig.desk.wish])
        await rig.set.idle()
        #expect(rig.windows.window(ghostty.key)?.frame == moved)
        #expect(rig.brought(ghostty, on: second) == nil)
    }

    @Test("定期核对：挪过来的窗口挪去了别的屏、或在 Snug 之外关了，销账，不再算能还原；最小化的照旧算")
    func verifySettlesBrought() async throws {
        let rig = try Rig()
        await rig.readyTwo(computer)
        rig.set.pull(ghostty, on: second)
        rig.set.pull(finder, on: second)
        rig.set.pull(notes, on: second)
        await rig.set.idle()
        rig.windows.setFrame(ghostty.key, CGRect(x: 40, y: 60, width: 800, height: 600))
        rig.windows.vanish(finder.key)
        _ = await rig.windows.setMinimized(notes.key, true)
        rig.set.verifyPlacement()
        await rig.set.idle()
        #expect(rig.brought(ghostty, on: second) == nil)
        #expect(rig.brought(finder, on: second) == nil)
        #expect(rig.brought(notes, on: second)?.original == notesHome)
        #expect(rig.broughtKeys(on: second) == [notes.key])
    }

    @Test("Snug 崩溃后再启动：电脑屏挪过来的窗口按各自的账放回原处")
    func recoverBrought() async throws {
        let tmp = try TempDir()
        do {
            let rig = try Rig(dataDirectory: tmp.url)
            await rig.readyTwo(computer)
            rig.set.pull(ghostty, on: second)
            rig.set.pull(finder, on: second)
            await rig.set.idle()
        }
        let rig = try Rig(dataDirectory: tmp.url)
        rig.windows.setFrame(ghostty.key, CGRect(x: 4100, y: 100, width: 1200, height: 800))
        rig.windows.setFrame(finder.key, CGRect(x: 4200, y: 200, width: 800, height: 500))
        rig.set.recover()
        await rig.set.idle()
        #expect(rig.windows.window(ghostty.key)?.frame == ghosttyHome)
        #expect(rig.windows.window(finder.key)?.frame == finderHome)
        #expect(rig.brought(ghostty, on: second) == nil)
        #expect(rig.brought(finder, on: second) == nil)
    }

    @Test("设着主屏时从外接屏挪到电脑屏的窗口：撤屏时先设回主屏（系统把新主屏上的窗口换回原主屏），照样按账放回外接屏")
    func broughtWhileMainReturnsHome() async throws {
        let rig = try Rig()
        let home = CGRect(x: -1800, y: 100, width: 800, height: 600)
        let xcode = WindowInfo(key: WindowKey(pid: 30, id: 50), app: "Xcode", bundleID: "com.apple.dt.Xcode", title: "snug")
        rig.windows.add(xcode.key, frame: home, info: xcode)
        var wish = rig.secondWish(computer)
        wish.main = true
        rig.set.setWishes([rig.desk.wish, wish])
        await rig.set.idle()
        let shift = try #require(rig.displays.bounds(102)).origin
        _ = await rig.windows.move(xcode.key, to: home.offsetBy(dx: -shift.x, dy: -shift.y))
        rig.set.pull(xcode, on: second)
        await rig.set.idle()
        // 设回原主屏时系统把新主屏上的窗口整体搬回原主屏（11-18 真机实测，见 how-it-works「窗口原位」）
        rig.arrangement.onChange = { [unowned windows = rig.windows] in
            windows.setFrame(xcode.key, CGRect(x: 300, y: 200, width: 800, height: 600))
        }
        rig.timeline.advance(10)
        rig.set.setWishes([rig.desk.wish])
        await rig.set.idle()
        #expect(rig.windows.window(xcode.key)?.frame == home)
        #expect(rig.brought(xcode, on: second) == nil)
    }

    @Test("从电脑屏转到手机屏：原位记录跟着走，电脑屏那份销掉；在手机上还原回到当初的原处")
    func transferFromComputer() async throws {
        let rig = try Rig()
        await rig.readyTwo(computer)
        rig.set.pull(ghostty, on: second)
        await rig.set.idle()
        await rig.pull(ghostty)
        #expect(rig.placed(on: .phone) == ghostty)
        #expect(rig.record?.original == ghosttyHome)
        #expect(rig.brought(ghostty, on: second) == nil)
        #expect(rig.broughtKeys(on: second) == [])
        rig.desk.putBack()
        await rig.set.idle()
        #expect(rig.windows.window(ghostty.key)?.frame == ghosttyHome)
    }

    // MARK: 设为主屏

    @Test("设为主屏：建好、善后之后设主屏；原主屏上的窗口跟着搬过去，不放回")
    func claimsMain() async throws {
        let rig = try Rig()
        var wish = rig.secondWish(computer)
        wish.main = true
        rig.set.setWishes([rig.desk.wish, wish])
        await rig.set.idle()
        #expect(rig.journal.all == ["snapshot", "create", "create", "restore", "main 102"])
        #expect(rig.arrangement.main == 102)
    }

    @Test("撤设成主屏的那块：先设回原主屏（窗口跟着回去），再清场、再撤")
    func releasesMainBeforeClearing() async throws {
        let rig = try Rig()
        var wish = rig.secondWish(computer)
        wish.main = true
        rig.set.setWishes([rig.desk.wish, wish])
        await rig.set.idle()
        rig.timeline.advance(10)
        rig.journal.clear()
        rig.set.setWishes([rig.desk.wish])
        await rig.set.idle()
        let arranged = try #require(rig.journal.all.firstIndex { $0.hasPrefix("arrange") })
        let retired = try #require(rig.journal.index(of: "retire 102"))
        #expect(arranged < retired)
        #expect(rig.arrangement.main == 1)
    }

    @Test("电脑屏切换只激活本屏窗口，窗口已移走时跳过")
    func desktopFocusPreservesWindow() async throws {
        let rig = try Rig()
        let wish = rig.secondWish(computer)
        rig.set.setWishes([wish])
        await rig.set.idle()
        let bounds = try #require(rig.displays.bounds(101))
        rig.windows.add(safari.key, frame: bounds, fullScreen: true, info: safari)
        rig.journal.clear()

        rig.set.focus(safari, on: wish.id)
        await rig.set.idle()
        #expect(rig.journal.all == ["focus \(safari.key.id)"])
        #expect(rig.windows.window(safari.key)?.frame == bounds)
        #expect(rig.windows.window(safari.key)?.fullScreen == true)

        let outside = bounds.offsetBy(dx: bounds.width, dy: 0)
        rig.windows.setFrame(safari.key, outside)
        rig.journal.clear()
        rig.set.focus(safari, on: wish.id)
        await rig.set.idle()
        #expect(rig.journal.all.isEmpty)
    }

    @Test("系统按这组屏幕记的排布已经把 Snug 的屏设成主屏（上次设了主屏没设回就崩了，同一次登录里再建）：原来的排布按 Snug 的屏出现前的主屏记，不再当主屏时还给它")
    func claimsMainAlreadyMadeBySystem() async throws {
        let rig = try Rig()
        rig.displays.onCreate = { [unowned arrangement = rig.arrangement] in
            arrangement.origins_ = [1: CGPoint(x: -1512, y: 0), 101: .zero]
        }
        var wish = rig.secondWish(computer)
        wish.main = true
        rig.set.setWishes([wish])
        await rig.set.idle()
        rig.set.setWishes([rig.secondWish(computer)])
        await rig.set.idle()
        #expect(rig.arrangement.main == 1)
        #expect(rig.arrangement.origins()[101] == CGPoint(x: 1512, y: 0))
    }

    @Test("设了主屏时放上屏的外接屏窗口：原位按没设主屏时的坐标记，不再当主屏、撤屏后回到原处")
    func placedWhileMainReturnsHome() async throws {
        let rig = try Rig()
        let home = CGRect(x: -1800, y: 100, width: 800, height: 600)
        let xcode = WindowInfo(key: WindowKey(pid: 30, id: 50), app: "Xcode", bundleID: "com.apple.dt.Xcode", title: "snug")
        rig.windows.add(xcode.key, frame: home, info: xcode)
        var wish = rig.secondWish(computer)
        wish.main = true
        rig.set.setWishes([rig.desk.wish, wish])
        await rig.set.idle()
        // 设成主屏的那块屏原来的原点：主屏的原点总在 (0,0)，别的屏连同上面的窗口一起平移了这么多
        let shift = try #require(rig.displays.bounds(102)).origin
        _ = await rig.windows.move(xcode.key, to: home.offsetBy(dx: -shift.x, dy: -shift.y))
        await rig.pull(xcode)
        wish.main = false
        rig.set.setWishes([rig.desk.wish, wish])
        await rig.set.idle()
        rig.timeline.advance(10)
        rig.set.setWishes([])
        await rig.set.idle()
        #expect(rig.windows.window(xcode.key)?.frame == home)
    }

    @Test("设着主屏时在屏上换窗口：原主屏上的窗口原位按原主屏记，换下来时放到设成主屏的那块屏上同一处（系统还原排布时把它带回原主屏，11-18 真机实测）")
    func swapWhileMainKeepsHomeMainWindowsOnMain() async throws {
        let rig = try Rig()
        rig.displays.others[1] = ScreenMode(ioModeID: 1, width: 1512, height: 982, pixelWidth: 3024, pixelHeight: 1964, refreshRate: 120)
        var wish = rig.secondWish(computer)
        wish.main = true
        rig.set.setWishes([rig.desk.wish, wish])
        await rig.set.idle()
        // 设成主屏的那块此刻的原点（真机上是 0,0）；原主屏跟着别的屏一起让开
        let main = try #require(rig.displays.bounds(102)).origin
        rig.displays.otherBounds[1] = CGRect(x: -main.x, y: -main.y, width: 1512, height: 982)
        // 原主屏 (152,73) 处的窗口，设主屏时被系统搬到新主屏的同一处
        let home = CGRect(x: 152, y: 73, width: 656, height: 422)
        let notes = WindowInfo(key: WindowKey(pid: 34, id: 54), app: "备忘录", bundleID: "com.apple.Notes", title: "清单")
        rig.windows.add(notes.key, frame: home.offsetBy(dx: main.x, dy: main.y), info: notes)
        await rig.pull(notes)
        #expect(rig.record(of: rig.desk.id)?.original == home)
        let memo = WindowInfo(key: WindowKey(pid: 35, id: 55), app: "文本编辑", bundleID: "com.apple.TextEdit", title: "t2")
        rig.windows.add(memo.key, frame: CGRect(x: main.x + 300, y: main.y + 300, width: 500, height: 300), info: memo)
        await rig.pull(memo)
        #expect(rig.windows.window(notes.key)?.frame == home.offsetBy(dx: main.x, dy: main.y))
    }

    @Test("设着主屏时窗口从远处的屏挪上屏被留在原处：中转用原来那块主屏，不用此刻当主屏的 Snug 屏")
    func pullThroughHomeMainWhileClaimed() async throws {
        let rig = try Rig()
        rig.displays.others[1] = ScreenMode(ioModeID: 1, width: 1512, height: 982, pixelWidth: 3024, pixelHeight: 1964, refreshRate: 120)
        var wish = rig.secondWish()
        wish.main = true
        rig.set.setWishes([rig.desk.wish, wish])
        await rig.set.idle()
        let main = try #require(rig.displays.bounds(102)).origin
        let home = CGRect(x: -main.x, y: -main.y, width: 1512, height: 982)
        rig.displays.otherBounds[1] = home
        let far = WindowInfo(key: WindowKey(pid: 20, id: 20), app: "WorkBuddy", bundleID: "com.example.workbuddy", title: "WorkBuddy")
        rig.windows.add(far.key, frame: CGRect(x: 2053, y: 1110, width: 1226, height: 816), info: far)
        rig.windows.requireStop(far.key, in: home)
        rig.set.pull(far, on: second)
        await rig.set.idle()
        #expect(rig.placed(on: second) == far)
        #expect(rig.windows.window(far.key)?.frame == rig.displays.windowArea(102, withHomeBar: true))
    }

    @Test("屏留着、只是不再当主屏：设回原主屏，屏不撤")
    func unsetMainKeepsScreen() async throws {
        let rig = try Rig()
        var wish = rig.secondWish(computer)
        wish.main = true
        rig.set.setWishes([wish])
        await rig.set.idle()
        rig.journal.clear()
        rig.set.setWishes([rig.secondWish(computer)])
        await rig.set.idle()
        #expect(rig.journal.all.filter { $0.hasPrefix("arrange") }.count == 1)
        #expect(!rig.journal.all.contains { $0.hasPrefix("retire") })
        #expect(rig.arrangement.main == 1)
    }

    @Test("同样的要求重复给：不重复设主屏")
    func claimsOnce() async throws {
        let rig = try Rig()
        var wish = rig.secondWish(computer)
        wish.main = true
        rig.set.setWishes([wish])
        await rig.set.idle()
        rig.set.setWishes([wish])
        await rig.set.idle()
        #expect(rig.journal.all.filter { $0.hasPrefix("main") }.count == 1)
    }

    @Test("设主屏失败：屏照常用，之后不再当主屏时不去摆排布")
    func mainFails() async throws {
        let rig = try Rig()
        rig.arrangement.fails = true
        var wish = rig.secondWish(computer)
        wish.main = true
        rig.set.setWishes([wish])
        await rig.set.idle()
        #expect(rig.set.state.desks[second]?.screen == .ready(101))
        rig.arrangement.fails = false
        rig.set.setWishes([rig.secondWish(computer)])
        await rig.set.idle()
        #expect(!rig.journal.all.contains { $0.hasPrefix("arrange") })
    }

    @Test("撤设成主屏的那块时摆不回去：它还是主屏，屏上剩下的窗口挪到原来的主屏上，不挪到这块马上要撤的屏上")
    func clearsToHomeMainWhenRestoreFails() async throws {
        let rig = try Rig()
        let home = CGRect(x: -1512, y: 0, width: 1512, height: 982)
        rig.displays.others[1] = ScreenMode(ioModeID: 1, width: 1512, height: 982, pixelWidth: 3024, pixelHeight: 1964, refreshRate: 120)
        rig.displays.otherBounds[1] = home
        var wish = rig.secondWish(computer)
        wish.main = true
        rig.set.setWishes([rig.desk.wish, wish])
        await rig.set.idle()
        rig.displays.mainOn = 102
        let bounds = try #require(rig.displays.bounds(102))
        let stray = WindowKey(pid: 33, id: 53)
        rig.windows.add(stray, frame: CGRect(origin: bounds.origin, size: CGSize(width: 400, height: 300)))
        rig.arrangement.fails = true
        rig.timeline.advance(10)
        rig.set.setWishes([rig.desk.wish])
        await rig.set.idle()
        let frame = try #require(rig.windows.window(stray)?.frame)
        #expect(home.contains(CGPoint(x: frame.midX, y: frame.midY)))
    }

    @Test("不再当主屏时摆不回去：原来的排布留着，再设主屏、再设回时摆回设主屏之前")
    func restoreFailsKeepsSavedOrigins() async throws {
        let rig = try Rig()
        var wish = rig.secondWish(computer)
        wish.main = true
        rig.set.setWishes([wish])
        await rig.set.idle()
        rig.arrangement.fails = true
        wish.main = false
        rig.set.setWishes([wish])
        await rig.set.idle()
        #expect(rig.arrangement.main == 101)
        rig.arrangement.fails = false
        wish.main = true
        rig.set.setWishes([wish])
        await rig.set.idle()
        wish.main = false
        rig.set.setWishes([wish])
        await rig.set.idle()
        #expect(rig.arrangement.main == 1)
        #expect(rig.arrangement.origins()[1] == .zero)
    }

    // MARK: 提前准备的屏

    /// 提前准备的那块手机屏：远程中放上 ghostty、用户在屏上直接开了个窗口，然后远程结束（屏留着）
    private func preparedSessionEnds(_ rig: Rig, before end: () -> Void = {}) async throws -> (memo: WindowInfo, frame: CGRect, display: DisplayID) {
        var wish = rig.desk.wish
        wish.prepared = true
        rig.set.setWishes([wish])
        await rig.set.idle()
        let display = try #require(rig.set.state.desks[.phone]?.display)
        rig.desk.setRemote(true)
        await rig.pull(ghostty)
        let memo = WindowInfo(key: WindowKey(pid: 30, id: 40), app: "备忘录", bundleID: "com.apple.Notes", title: "手机上新开的")
        let memoFrame = CGRect(x: phoneArea.minX + 20, y: phoneArea.minY + 40, width: 300, height: 200)
        rig.windows.add(memo.key, frame: memoFrame, info: memo)
        end()
        rig.set.setWishes([])
        rig.set.setWishes([wish])
        rig.desk.setRemote(false)
        await rig.set.idle()
        return (memo, memoFrame, display)
    }

    @Test("提前准备的屏，远程结束：屏留着；Snug 放的窗口按账归位、销账，用户在屏上直接开的挪到主屏居中（本机看不见这块屏）")
    func preparedScreenEndsSession() async throws {
        let rig = try Rig()
        let (memo, memoFrame, display) = try await preparedSessionEnds(rig)
        #expect(rig.set.state.desks[.phone]?.display == display)
        #expect(rig.windows.window(ghostty.key)?.frame == ghosttyHome)
        #expect(rig.windows.window(ghostty.key)?.zoom == 0)
        #expect(rig.placed(on: .phone) == nil)
        #expect(rig.record == nil)
        #expect(rig.windows.window(memo.key)?.frame == FakeDisplays.main.centered(memoFrame.size))
    }

    @Test("提前准备的屏，远程结束时放不回去的窗口（字号缩不回）：照旧算放着、账留着，也不当成用户的窗口挪去主屏；别的照常挪")
    func preparedScreenKeepsStuckWindow() async throws {
        let rig = try Rig()
        let (memo, memoFrame, _) = try await preparedSessionEnds(rig) { rig.windows.blockZoom() }
        #expect(rig.placed(on: .phone) == ghostty)
        #expect(rig.record?.window == ghostty.key)
        #expect(rig.windows.window(ghostty.key)?.frame == phoneArea)
        #expect(rig.windows.window(memo.key)?.frame == FakeDisplays.main.centered(memoFrame.size))
    }

    @Test("提前准备的屏，远程结束：窗口放上来时换宽了一档的屏，归位后换回基准宽度")
    func preparedScreenRestoresWidth() async throws {
        let rig = try Rig()
        var wish = rig.desk.wish
        wish.prepared = true
        rig.set.setWishes([wish])
        await rig.set.idle()
        rig.desk.setRemote(true)
        rig.windows.setMinSize(finder.key, width: 740)
        await rig.pull(finder)
        rig.journal.clear()
        rig.desk.setRemote(false)
        await rig.set.idle()
        #expect(rig.journal.all.last == "width 101 540")
    }

    @Test("屏要留着时（只在启动时认屏的远程中的常驻屏）在手机上退出：屏不撤、编号不变；Snug 放的窗口归位，用户在上面开的挪到主屏，提示屏幕保留")
    func keptOnDismiss() async throws {
        let rig = try Rig()
        var wish = rig.desk.wish
        wish.prepared = true
        wish.staysOnDismiss = true
        rig.set.setWishes([wish])
        await rig.set.idle()
        let display = try #require(rig.set.state.desks[.phone]?.display)
        rig.desk.setRemote(true)
        await rig.pull(ghostty)
        let memo = WindowInfo(key: WindowKey(pid: 30, id: 40), app: "备忘录", bundleID: "com.apple.Notes", title: "手机上新开的")
        let memoFrame = CGRect(x: phoneArea.minX + 20, y: phoneArea.minY + 40, width: 300, height: 200)
        rig.windows.add(memo.key, frame: memoFrame, info: memo)
        rig.timeline.advance(10)
        rig.set.dismissScreen(.phone)
        await rig.set.idle()
        let phone = try #require(rig.set.state.desks[.phone])
        #expect(phone.display == display)
        #expect(rig.set.state.dismissed.isEmpty)
        #expect(rig.placed(on: .phone) == nil)
        #expect(rig.windows.window(ghostty.key)?.frame == ghosttyHome)
        #expect(rig.windows.window(memo.key)?.frame == FakeDisplays.main.centered(memoFrame.size))
        #expect(phone.notice == .keptOnDismiss)
        #expect(phone.work == nil)
        // 同一次远程里再算一遍要哪些屏：屏照旧在，编号不变
        rig.set.setWishes([wish])
        await rig.set.idle()
        #expect(rig.set.state.desks[.phone]?.display == display)
    }

    @Test("预览自测的屏（不是提前准备的）：远程结束时不动，窗口照旧放着（开发者正看着）")
    func previewScreenUntouchedAtSessionEnd() async throws {
        let rig = try Rig()
        rig.set.setWishes([rig.desk.wish])
        await rig.set.idle()
        rig.desk.setRemote(true)
        await rig.pull(ghostty)
        rig.desk.setRemote(false)
        await rig.set.idle()
        #expect(rig.placed(on: .phone) == ghostty)
        #expect(rig.windows.window(ghostty.key)?.frame == phoneArea)
    }

    @Test("提前准备的屏，远程结束后又连上（同一拍里）：屏上的窗口留给这一次，不归位")
    func preparedScreenReconnects() async throws {
        let rig = try Rig()
        var wish = rig.desk.wish
        wish.prepared = true
        rig.set.setWishes([wish])
        await rig.set.idle()
        rig.desk.setRemote(true)
        await rig.pull(ghostty)
        rig.desk.setRemote(false)
        rig.desk.setRemote(true)
        await rig.set.idle()
        #expect(rig.placed(on: .phone) == ghostty)
        #expect(rig.windows.window(ghostty.key)?.frame == phoneArea)
    }

    // MARK: 设为主屏常驻（issue #28）

    @Test("设为主屏的那块常驻：远程结束时不撤、仍是主屏，屏上的窗口原样留着（账也留着，下次连上接着用）；没设主屏的那块照旧撤")
    func persistentMainSurvivesSessionEnd() async throws {
        let rig = try Rig()
        let home = CGRect(x: -1800, y: 100, width: 800, height: 600)
        let xcode = WindowInfo(key: WindowKey(pid: 30, id: 50), app: "Xcode", bundleID: "com.apple.dt.Xcode", title: "snug")
        rig.windows.add(xcode.key, frame: home, info: xcode)
        var main = rig.secondWish()
        main.main = true
        rig.desk.setRemote(true)
        rig.set.setWishes([rig.desk.wish, main])
        await rig.set.idle()
        // 设主屏时别的屏连同上面的窗口一起平移
        let shift = try #require(rig.displays.bounds(102)).origin
        let shifted = home.offsetBy(dx: -shift.x, dy: -shift.y)
        _ = await rig.windows.move(xcode.key, to: shifted)
        rig.set.pull(xcode, on: second)
        await rig.set.idle()
        #expect(rig.placed(on: second) == xcode)
        let filled = try #require(rig.windows.window(xcode.key)?.frame)
        rig.timeline.advance(10)
        rig.journal.clear()
        // 远程结束：AppController 先说一块屏都不要，再按「不在远程」重算（只剩常驻的主屏），再告诉 DeskSet
        rig.set.setWishes([])
        rig.set.setWishes([main])
        rig.desk.setRemote(false)
        await rig.set.idle()
        #expect(rig.journal.all.contains("retire 101"))
        #expect(!rig.journal.all.contains("retire 102"))
        #expect(!rig.journal.all.contains { $0.hasPrefix("arrange") })
        #expect(rig.arrangement.main == 102)
        #expect(rig.placed(on: second) == xcode)
        #expect(rig.record(of: second)?.window == xcode.key)
        #expect(rig.windows.window(xcode.key)?.frame == filled)
        #expect(!rig.journal.all.contains { $0.hasPrefix("move 50") })
        // 取消设为主屏、没人远程：这块屏撤掉，窗口这时才放回原处
        rig.timeline.advance(10)
        rig.set.setWishes([])
        await rig.set.idle()
        #expect(rig.record(of: second) == nil)
        #expect(rig.windows.window(xcode.key)?.frame == home)
    }

    @Test("远程中取消主屏、屏留着：系统还原排布时把屏上放着的窗口换去了原主屏（资源库开着，不会自己铺回来）：挪回来，仍算放在屏上")
    func releaseMainReclaimsPlaced() async throws {
        let rig = try Rig()
        var main = rig.secondWish()
        main.main = true
        rig.desk.setRemote(true)
        rig.set.setWishes([rig.desk.wish, main])
        await rig.set.idle()
        rig.set.pull(ghostty, on: second)
        await rig.set.idle()
        rig.set.showList(on: second)
        await rig.set.idle()
        // 11-18 真机：还原排布时新主屏上的窗口整体换到原主屏
        rig.arrangement.onChange = { [unowned windows = rig.windows] in
            windows.setFrame(ghostty.key, CGRect(x: 300, y: 200, width: 540, height: 900))
        }
        rig.set.setWishes([rig.desk.wish, rig.secondWish()])
        await rig.set.idle()
        #expect(rig.placed(on: second) == ghostty)
        #expect(rig.windows.window(ghostty.key)?.frame == rig.displays.windowArea(102, withHomeBar: true))
        #expect(rig.record(of: second)?.window == ghostty.key)
    }

    @Test("远程中设主屏：系统把这块屏上放着的窗口换去了原主屏：挪回来")
    func claimMainReclaimsPlaced() async throws {
        let rig = try Rig()
        rig.desk.setRemote(true)
        rig.set.setWishes([rig.desk.wish, rig.secondWish()])
        await rig.set.idle()
        rig.set.pull(ghostty, on: second)
        await rig.set.idle()
        rig.arrangement.onChange = { [unowned windows = rig.windows] in
            windows.setFrame(ghostty.key, CGRect(x: 300, y: 200, width: 540, height: 900))
        }
        var main = rig.secondWish()
        main.main = true
        rig.set.setWishes([rig.desk.wish, main])
        await rig.set.idle()
        #expect(rig.arrangement.main == 102)
        #expect(rig.placed(on: second) == ghostty)
        #expect(rig.windows.window(ghostty.key)?.frame == rig.displays.windowArea(102, withHomeBar: true))
    }

    @Test("远程中取消主屏、电脑屏留着：挪过来的窗口被系统换走，挪回电脑屏，账照旧；之后定期核对不当成用户自己挪走")
    func releaseMainReclaimsBrought() async throws {
        let rig = try Rig()
        var wish = rig.secondWish(computer)
        wish.main = true
        rig.desk.setRemote(true)
        rig.set.setWishes([rig.desk.wish, wish])
        await rig.set.idle()
        rig.set.pull(finder, on: second)
        await rig.set.idle()
        #expect(rig.broughtKeys(on: second) == [finder.key])
        rig.arrangement.onChange = { [unowned windows = rig.windows] in windows.setFrame(finder.key, finderHome) }
        wish.main = false
        rig.set.setWishes([rig.desk.wish, wish])
        await rig.set.idle()
        rig.desk.verifyPlacement()
        await rig.set.idle()
        #expect(rig.broughtKeys(on: second) == [finder.key])
        let area = try #require(rig.displays.windowArea(102, withHomeBar: false))
        #expect(rig.windows.window(finder.key)?.frame == area.centered(finderHome.size))
    }

    @Test("远程结束后马上又连上（收尾还排在队里）：上一次的提示照样收掉，不带到这一次")
    func quickReconnectForgetsSession() async throws {
        let rig = try Rig()
        let codex = AppInfo(bundleID: "com.openai.codex", name: "ChatGPT", path: "/Applications/ChatGPT.app")
        rig.desk.setRemote(true)
        rig.set.setWishes([rig.desk.wish])
        await rig.set.idle()
        let app = rig.apps.run(codex, pid: 600)
        rig.apps.onQuit(codex, .stalls)
        rig.desk.quit(app)
        await rig.set.idle()
        #expect(rig.desk.state.notice == .quitStalled(app: "ChatGPT", pid: 600))
        // 这一拍远程结束（AppController.handle：先不要屏、再按计划要、再报不在远程），下一拍又连上，收尾轮到时已经又在远程
        rig.set.setWishes([])
        rig.set.setWishes([])
        rig.desk.setRemote(false)
        rig.set.setWishes([rig.desk.wish])
        rig.desk.setRemote(true)
        await rig.set.idle()
        #expect(rig.desk.state.notice == nil)
    }

    @Test("常驻的主屏：这次远程留在屏上的提示，远程结束时收掉，不带到下一次")
    func persistentMainForgetsSession() async throws {
        let rig = try Rig()
        let codex = AppInfo(bundleID: "com.openai.codex", name: "ChatGPT", path: "/Applications/ChatGPT.app")
        var main = rig.desk.wish
        main.main = true
        rig.desk.setRemote(true)
        rig.set.setWishes([main])
        await rig.set.idle()
        let app = rig.apps.run(codex, pid: 600)
        rig.apps.onQuit(codex, .stalls)
        rig.desk.quit(app)
        await rig.set.idle()
        #expect(rig.desk.state.notice == .quitStalled(app: "ChatGPT", pid: 600))
        rig.set.setWishes([])
        rig.set.setWishes([main])
        rig.desk.setRemote(false)
        await rig.set.idle()
        #expect(rig.desk.state.notice == nil)
        #expect(rig.set.state.desks[.phone]?.screen == .ready(101))
    }

    @Test("常驻的主屏、不在远程：带着屏上大小回来的窗口不当成「还在远程」接着放，放回原位")
    func persistentMainIdleReturnGoesHome() async throws {
        let rig = try Rig()
        var main = rig.desk.wish
        main.main = true
        rig.desk.setRemote(true)
        rig.set.setWishes([main])
        await rig.set.idle()
        await rig.pull(ghostty)
        let filled = try #require(rig.windows.window(ghostty.key)?.frame)
        rig.windows.vanish(ghostty.key)
        rig.desk.verifyPlacement()
        await rig.set.idle()
        rig.timeline.advance(10)
        rig.set.setWishes([])
        rig.set.setWishes([main])
        rig.desk.setRemote(false)
        await rig.set.idle()
        // 窗口在 Snug 之外关掉后又开出来，还是屏上铺成的样子、落在常驻屏上
        let back = WindowInfo(key: WindowKey(pid: 10, id: 70), app: ghostty.app, bundleID: ghostty.bundleID, title: ghostty.title)
        rig.windows.add(back.key, frame: filled, info: back)
        rig.desk.checkReturns()
        await rig.set.idle()
        #expect(rig.placed(on: .phone) == nil)
        #expect(rig.windows.window(back.key)?.frame == ghosttyHome)
    }
}
