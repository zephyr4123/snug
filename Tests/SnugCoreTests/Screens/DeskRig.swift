import CoreGraphics
import Foundation
@testable import SnugCore

// 屏幕调度的测试装置：一套假系统 + 一个 DeskSet，和几个常用的窗口。
// 大多数用例只用一块竖屏手机屏（OneScreen：把 DeskSet 当成只有这一块屏来用，和 2.5 以前的手机屏一样）

let ghostty = WindowInfo(key: WindowKey(pid: 10, id: 7), app: "Ghostty", bundleID: "com.mitchellh.ghostty", title: "~/snug")
let finder = WindowInfo(key: WindowKey(pid: 11, id: 8), app: "Finder", bundleID: "com.apple.finder", title: "下载")
let safari = WindowInfo(key: WindowKey(pid: 12, id: 9), app: "Safari", bundleID: "com.apple.Safari", title: "GitHub")
let notes = WindowInfo(key: WindowKey(pid: 13, id: 10), app: "备忘录", bundleID: "com.apple.Notes", title: "清单")
let ghosttyHome = CGRect(x: 100, y: 100, width: 1200, height: 800)
let finderHome = CGRect(x: 300, y: 200, width: 800, height: 500)
let safariHome = CGRect(x: 0, y: 25, width: 1512, height: 920)
/// Safari 退出全屏后的平时位置
let safariWindowed = CGRect(x: 200, y: 100, width: 1000, height: 700)
let notesHome = CGRect(x: 400, y: 300, width: 700, height: 500)
let phoneArea = FakeDisplays.area(width: ScreenFit.standard.baseWidth)

/// 一套假系统 + 一个 DeskSet。每个用例一个临时数据目录
@MainActor
final class Rig {
    let tmp: TempDir
    let paths: SnugPaths
    let journal = Journal()
    let displays: FakeDisplays
    let arrangement: FakeArrangement
    let windows: FakeWindows
    let apps: FakeApps
    let timeline = ManualTimeline()
    let set: DeskSet
    /// 只用其中一块手机屏时的样子
    let desk: OneScreen

    init(dataDirectory: URL? = nil) throws {
        let tmp = try TempDir()
        let dir = tmp.url
        self.tmp = tmp
        paths = SnugPaths(dataDirectory: dataDirectory ?? dir, logFile: dir.appendingPathComponent("Snug.log"))
        displays = FakeDisplays(journal: journal)
        arrangement = FakeArrangement(journal: journal)
        arrangement.displays = displays
        windows = FakeWindows(journal: journal, ledger: paths.placedRecord(for: .phone))
        windows.add(ghostty.key, frame: ghosttyHome, info: ghostty)
        windows.add(finder.key, frame: finderHome, info: finder)
        windows.add(safari.key, frame: safariHome, fullScreen: true, windowed: safariWindowed, info: safari)
        windows.add(notes.key, frame: notesHome, minimized: true, info: notes)
        apps = FakeApps(journal: journal, windows: windows, timeline: timeline)
        set = DeskSet(displays: displays, windows: windows, apps: apps, arrangement: arrangement, timeline: timeline, paths: paths)
        desk = OneScreen(set)
        let timeline = timeline
        displays.clock = { timeline.now }
        windows.clock.withLock { $0 = { timeline.now } }
    }

    var record: PlacedRecord? { RestoreRecord<PlacedRecord>(url: paths.placedRecord(for: .phone)).pending() }

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

/// 从 2.5 迁来的那块手机屏的身份：跟着迁移代码走，迁移身份改了测试装置也跟着变
let phoneSpec = ScreenPlan.spec(of: ScreenConfig.legacyPhone(.standard, enabled: true))

/// 把 DeskSet 当成只有一块手机屏来用：意图都发给这一块，状态把这块屏的和全局的合在一起
@MainActor
final class OneScreen {
    struct State: Equatable {
        var screen = ScreenSet.State.off
        var placed: Desk.Placed?
        var listVisible = true
        var work: Desk.Work?
        var notice: Desk.Notice?
        var quitting: Set<Int32> = []
        var closing: Set<WindowKey> = []
        var dismissed = false
        var closeButton: CloseButton?
        var display: DisplayID? { screen.display }
    }

    let desks: DeskSet
    let id = ScreenID.phone
    private(set) var fit = ScreenFit.standard
    private var wanted = false
    private var last = State()

    init(_ set: DeskSet) {
        desks = set
        set.onChange = { [weak self] _ in
            guard let self else { return }
            let now = state
            guard now != last else { return }
            last = now
            onChange?(now)
        }
    }

    var onChange: ((State) -> Void)?
    var onGone: ((DeskSet.Gone) -> Void)? {
        get { desks.onGone }
        set { desks.onGone = newValue }
    }
    var onTopologyChange: (() -> Void)? {
        get { desks.onTopologyChange }
        set { desks.onTopologyChange = newValue }
    }

    var state: State {
        let s = desks.state
        let d = s.desks[id] ?? Desk.State()
        return State(screen: d.screen, placed: d.placed, listVisible: d.listVisible, work: d.work, notice: d.notice,
                     quitting: s.quitting, closing: s.closing, dismissed: s.dismissed.contains(id), closeButton: d.closeButton)
    }

    var wish: ScreenWish { ScreenWish(id: id, spec: phoneSpec, fit: fit, behavior: .touchScreen) }

    func setWanted(_ on: Bool) {
        wanted = on
        desks.setWishes(on ? [wish] : [])
    }

    func setFit(_ fit: ScreenFit) {
        self.fit = fit
        if wanted { desks.setWishes([wish]) }
    }

    func pull(_ w: WindowInfo) { desks.pull(w, on: id) }
    func open(_ app: AppInfo) { desks.open(app, on: id) }
    func newWindow(_ app: RunningApp) { desks.newWindow(app, on: id) }
    func quit(_ app: RunningApp) { desks.quit(app, from: id) }
    func forceQuit(pid: Int32, app: String) { desks.forceQuit(pid: pid, app: app, from: id) }
    func close(_ w: WindowInfo) { desks.close(w, from: id) }
    func closePlaced(window: UInt32) { desks.closePlaced(window: window) }
    func dismissNotice() { desks.dismissNotice(on: id) }
    func showList() { desks.showList(on: id) }
    func returnToPlaced() { desks.returnToPlaced(on: id) }
    func putBack() { desks.putBack(on: id) }
    func zoom(by delta: Int) { desks.zoom(by: delta, on: id) }
    func toggleSidebar() async -> Bool { await desks.toggleSidebar(on: id) }
    func dismissScreen() { desks.dismissScreen(id) }
    func setDefaultZoom(_ steps: Int) { desks.setDefaultZoom(steps) }
    func displaysChanged() { desks.displaysChanged() }
    func verifyPlacement() { desks.verifyPlacement() }
    func setRemote(_ on: Bool) { desks.setRemote(on) }
    func settleDisplays() { desks.settleDisplays() }
    func recover() { desks.recover() }
    func checkReturns() { desks.checkReturns() }
    func shutdown() async {
        wanted = false
        await desks.shutdown()
    }
    func idle() async { await desks.idle() }
}
