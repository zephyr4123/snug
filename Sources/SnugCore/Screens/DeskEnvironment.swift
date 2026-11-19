// 几块屏共用的：系统能力、时钟、屏幕模块，和两本跨屏的账（字号簿、留下的账）。
// DeskSet 建一份，交给每块 Desk；Desk 只经它碰共用的东西，不认别的 Desk
import CoreGraphics
import Foundation

@MainActor
final class DeskEnvironment {
    let windows: any WindowControl
    let apps: any AppControl
    let timeline: any Timeline
    let screens: ScreenSet
    let paths: SnugPaths
    /// 设置里的默认字号级数
    var defaultZoom: Int
    /// 每个 App 在手机、平板屏上记住的字号级数
    var zoomBook: ZoomBook
    /// 在 Snug 屏上被 Snug 之外关掉的窗口欠下的账（见 LeftBehindLedger）
    let leftBehind: LeftBehindLedger
    private let zoomFile: JSONFile<ZoomBook>

    init(windows: any WindowControl, apps: any AppControl, timeline: any Timeline, screens: ScreenSet,
         paths: SnugPaths, defaultZoom: Int) {
        self.windows = windows
        self.apps = apps
        self.timeline = timeline
        self.screens = screens
        self.paths = paths
        self.defaultZoom = defaultZoom
        zoomFile = JSONFile(url: paths.zoomBook)
        zoomBook = zoomFile.loadOrQuarantine() ?? ZoomBook()
        leftBehind = LeftBehindLedger(url: paths.leftBehind, windows: windows, apps: apps)
    }

    /// 原位，按没设主屏时的坐标记（见 ScreenSet.homeFrame）。落在 Snug 屏上的（App 按上次记住的位置把窗口开在了那块屏上）
    /// 改成原来那块主屏居中，屏一撤那个位置就不存在了。设成主屏的那块除外：上面的窗口还原排布时系统会搬回原主屏同一处
    func originalFrame(_ frame: CGRect) -> CGRect {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        guard !screens.onClaimedScreen(center), screens.screen(at: center) != nil, let home = screens.homeMainArea() else {
            return screens.homeFrame(frame)
        }
        return screens.homeFrame(home.centered(frame.size))
    }

    func rememberOriginal(_ frame: CGRect, in record: inout PlacedRecord, useDesktopSnapshot: Bool) {
        if useDesktopSnapshot, let (saved, anchor) = screens.savedDesktopFrame(for: record.window) {
            record.original = saved
            record.originalDisplay = anchor
        } else {
            record.original = originalFrame(frame)
            record.originalDisplay = screens.displayAnchor(for: record.original)
        }
    }

    /// 读不到、挪不动的窗口：是关了，还是 App 没响应
    func unreachable(_ window: WindowInfo) async -> Desk.Notice {
        await windows.exists(window.key) ? .windowUnresponsive(app: window.app) : .windowGone(app: window.app)
    }

    func saveZoomBook() {
        do {
            try zoomFile.save(zoomBook)
        } catch {
            Log.error("记不住字号级数（zoom.json 写不进去）：\(error)")
        }
    }
}

extension CGRect {
    /// 在这块区域里居中放一个 size 大小的框，大小不超过区域
    func centered(_ size: CGSize) -> CGRect {
        let size = CGSize(width: min(size.width, width), height: min(size.height, height))
        return CGRect(x: (midX - size.width / 2).rounded(), y: (midY - size.height / 2).rounded(), width: size.width, height: size.height)
    }
}
