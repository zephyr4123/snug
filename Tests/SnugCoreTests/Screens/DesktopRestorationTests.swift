import CoreGraphics
import Testing
@testable import SnugCore

@MainActor
struct DesktopRestorationTests {
    private let desktop = CGRect(x: 1512, y: -327, width: 1920, height: 1050)
    private let temporary = CGRect(x: 1512, y: -327, width: 1588, height: 1050)

    @Test("撤屏前窗口只能保持临时尺寸，撤屏后恢复原尺寸")
    func originalGeometryIsRetriedAfterRetire() async throws {
        let rig = try Rig()
        rig.displays.nudged[101] = CGVector(dx: 2200, dy: 0)
        rig.windows.setFrame(ghostty.key, desktop)
        await rig.ready()
        await rig.pull(ghostty)
        #expect(rig.record?.original == desktop)
        rig.windows.setFrame(ghostty.key, temporary)
        rig.windows.ignoreMoves()
        rig.displays.onRetire = { [windows = rig.windows] in windows.ignoreMoves(false) }
        rig.desk.setWanted(false)
        await rig.desk.idle()
        #expect(rig.windows.window(ghostty.key)?.frame == desktop)
    }

    @Test("加屏时镜像把窗口压窄，按镜像前的桌面快照记录原尺寸")
    func placementUsesFrameFromBeforeTemporaryShrink() async throws {
        let rig = try Rig()
        rig.windows.setFrame(ghostty.key, desktop)
        rig.displays.onCreate = { [unowned displays = rig.displays, windows = rig.windows] in
            displays.mirrors = [101]
            windows.setFrame(ghostty.key, CGRect(x: 0, y: 30, width: 537, height: 886))
            windows.ignoreMoves()
        }
        await rig.ready()
        rig.windows.ignoreMoves(false)
        await rig.pull(ghostty)
        #expect(rig.record?.original == desktop)
        rig.desk.setWanted(false)
        await rig.desk.idle()
        #expect(rig.windows.window(ghostty.key)?.frame == desktop)
    }

    @Test("手机屏休眠时延迟下线，外屏原点变化后按相对位置归位")
    func waitsForOfflineAndRestoresDisplayRelativeFrame() async throws {
        let rig = try Rig()
        let external = CGRect(x: 1512, y: -357, width: 2560, height: 1440)
        let mode = ScreenMode(ioModeID: 1, width: 2560, height: 1440, pixelWidth: 5120, pixelHeight: 2880, refreshRate: 60)
        rig.displays.others = [2: mode]
        rig.displays.otherBounds = [2: external]
        rig.displays.nudged[101] = CGVector(dx: 2200, dy: 0)
        rig.windows.setFrame(ghostty.key, desktop)
        await rig.ready()
        await rig.pull(ghostty)
        let onPhone = rig.windows.window(ghostty.key)?.frame
        rig.displays.staysOnline = true
        rig.displays.onRetire = { [unowned displays = rig.displays] in
            displays.otherBounds[2] = external.offsetBy(dx: -972, dy: 40)
        }
        rig.desk.setWanted(false)
        await rig.desk.idle()
        rig.desk.recover()
        await rig.desk.idle()
        #expect(rig.windows.window(ghostty.key)?.frame == onPhone)
        #expect(rig.record?.zoom == 0)

        rig.displays.goOffline(101)
        rig.desk.settleDisplays()
        await rig.desk.idle()
        #expect(rig.windows.window(ghostty.key)?.frame == desktop.offsetBy(dx: -972, dy: 40))
        #expect(rig.record == nil)
    }

    @Test("iTerm2 放大后断开，通过恢复文本大小菜单归位")
    func iTermRestoresTextFromMenu() async throws {
        let rig = try Rig()
        let terminal = WindowInfo(key: WindowKey(pid: 22, id: 23), app: "iTerm2", bundleID: "com.googlecode.iterm2", title: "")
        rig.windows.add(terminal.key, frame: desktop, info: terminal)
        rig.displays.nudged[101] = CGVector(dx: 2200, dy: 0)
        await rig.ready()
        await rig.pull(terminal)
        #expect(rig.record?.zoom == 2)
        rig.desk.setWanted(false)
        await rig.desk.idle()
        #expect(rig.journal.all.contains("restore text 23 ✎"))
        #expect(rig.windows.window(terminal.key)?.zoom == 0)
        #expect(rig.windows.window(terminal.key)?.frame == desktop)
        #expect(rig.record == nil)
    }
}
