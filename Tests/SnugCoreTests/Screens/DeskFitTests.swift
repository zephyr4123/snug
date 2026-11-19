import CoreGraphics
import Testing
@testable import SnugCore

/// 换了手机型号（16:9 的 iPhone 8）：基准 620×802
private let iPhone8 = ScreenFit(device: DeviceScreen(width: 750, height: 1334, points: 375), kind: .phone, orientation: .portrait)

@Suite("一块屏的调度：换型号")
@MainActor
struct DeskFitTests {
    @Test("没有手机屏时换：不动屏，下次加屏按新比例建、切到它的基准宽度")
    func withoutScreen() async throws {
        let rig = try Rig()
        rig.desk.setFit(iPhone8)
        await rig.desk.idle()
        #expect(rig.journal.all.isEmpty)
        await rig.ready()
        #expect(rig.displays.fits[101] == iPhone8)
        #expect(rig.displays.widths[101] == 620)
    }

    @Test("刚要加屏时换：按新比例建，不再换一遍")
    func whilePreparing() async throws {
        let rig = try Rig()
        rig.desk.setWanted(true)
        rig.desk.setFit(iPhone8)
        await rig.desk.idle()
        #expect(rig.journal.all.filter { $0 == "create" }.count == 1)
        #expect(!rig.journal.all.contains { $0.hasPrefix("reshape") })
        #expect(rig.displays.fits[101] == iPhone8)
    }

    @Test("露着列表时换：在线换比例，屏不撤、编号不变；换的时候是「正在调整」")
    func listVisible() async throws {
        let rig = try Rig()
        await rig.ready()
        rig.desk.setFit(iPhone8)
        #expect(rig.desk.state.work == .reshaping)
        await rig.desk.idle()
        #expect(rig.journal.all == ["reshape 101 620×802"])
        #expect(rig.desk.state.screen == .ready(101))
        #expect(rig.desk.state.work == nil)
        // UU 要切走再切回来才按新尺寸推流：提示一句
        #expect(rig.desk.state.notice == .reshaped)
        #expect(rig.displays.widths[101] == 620)
    }

    @Test("放着窗口时换：窗口按新比例重新铺满")
    func windowShown() async throws {
        let rig = try Rig()
        await rig.ready()
        await rig.pull(finder)
        rig.journal.clear()
        rig.desk.setFit(iPhone8)
        await rig.desk.idle()
        let area = FakeDisplays.area(width: 620, fit: iPhone8)
        #expect(rig.journal.all.first == "reshape 101 620×802")
        #expect(rig.windows.window(finder.key)?.frame == area)
        #expect(rig.desk.state.listVisible == false)
    }

    @Test("手机换成 iPad 后已放置的窗口让出更薄的底栏，换到更宽一档时仍与底栏贴齐", arguments: Orientation.allCases)
    func tabletHomeBar(orientation: Orientation) async throws {
        let phone = ScreenPlan.fit(.standard, orientation)
        let mini = DeviceChoice(model: nil, screen: DeviceScreen(width: 1488, height: 2266, points: 744), kind: .tablet)
        let tablet = ScreenPlan.fit(mini, orientation)
        let rig = try Rig()
        rig.desk.setFit(phone)
        await rig.ready()
        await rig.pull(finder)
        func bottomGap(for window: WindowInfo) throws -> CGFloat {
            let screen = try #require(rig.displays.bounds(101))
            let frame = try #require(rig.windows.window(window.key)?.frame)
            return screen.maxY - frame.maxY
        }
        #expect(try bottomGap(for: finder) == (orientation == .portrait ? 28 : 27))

        rig.desk.setFit(tablet)
        await rig.desk.idle()
        #expect(rig.set.state.desks[.phone]?.homeBarStyle == .tablet)
        #expect(try bottomGap(for: finder) == 24)

        rig.windows.setMinSize(notes.key, width: CGFloat(tablet.baseWidth + 100))
        await rig.pull(notes)
        #expect(rig.displays.widths[101] == tablet.baseWidth + 100)
        #expect(try bottomGap(for: notes) == (orientation == .portrait ? 29 : 27))

        rig.displays.reshapeFails = true
        rig.desk.setFit(phone)
        await rig.desk.idle()
        #expect(rig.set.state.desks[.phone]?.homeBarStyle == .tablet)
        #expect(try bottomGap(for: notes) == (orientation == .portrait ? 29 : 27))
    }

    @Test("窗口放着但露着列表时换：先不挪窗口，回到它时按新比例铺满")
    func windowBehindList() async throws {
        let rig = try Rig()
        await rig.ready()
        await rig.pull(finder)
        rig.desk.showList()
        await rig.desk.idle()
        rig.desk.setFit(iPhone8)
        await rig.desk.idle()
        #expect(rig.windows.window(finder.key)?.frame == phoneArea)
        rig.desk.returnToPlaced()
        await rig.desk.idle()
        #expect(rig.windows.window(finder.key)?.frame == FakeDisplays.area(width: 620, fit: iPhone8))
    }

    @Test("App 限定了最小宽度：按新比例的档位换到装得下它的一档")
    func minimumWidth() async throws {
        let rig = try Rig()
        rig.windows.setMinSize(finder.key, width: 740)
        await rig.ready()
        await rig.pull(finder)
        rig.desk.setFit(iPhone8)
        await rig.desk.idle()
        #expect(rig.displays.widths[101] == 740)
        #expect(rig.windows.window(finder.key)?.frame == FakeDisplays.area(width: 740, fit: iPhone8))
    }

    @Test("连着换了两次又换回原来的：已经是这个比例就不动屏")
    func backAndForth() async throws {
        let rig = try Rig()
        await rig.ready()
        rig.desk.setFit(iPhone8)
        rig.desk.setFit(.standard)
        await rig.desk.idle()
        #expect(rig.journal.all.isEmpty)
        #expect(rig.desk.state.work == nil)
    }

    @Test("换不成之后照旧按屏上的比例选档：回到列表还是原来的基准宽度，新放的窗口也按原来的档位铺")
    func afterFailure() async throws {
        let rig = try Rig()
        rig.displays.reshapeFails = true
        await rig.ready()
        rig.desk.setFit(iPhone8)
        await rig.desk.idle()
        await rig.pull(finder)
        #expect(rig.windows.window(finder.key)?.frame == phoneArea)
        rig.desk.showList()
        await rig.desk.idle()
        #expect(rig.displays.widths[101] == 540)
        #expect(!rig.journal.all.contains("width 101 620"))
    }

    @Test("正在放窗口时换：不冲掉「正在打开」，放完轮到换比例时才写「正在调整」")
    func whileBusy() async throws {
        let rig = try Rig()
        await rig.ready()
        var works: [Desk.Work?] = []
        rig.desk.onChange = { works.append($0.work) }
        rig.desk.pull(finder)
        rig.desk.setFit(iPhone8)
        #expect(rig.desk.state.work == .placing(finder))
        await rig.desk.idle()
        #expect(works.contains(.reshaping))
        #expect(rig.desk.state.work == nil)
        #expect(rig.windows.window(finder.key)?.frame == FakeDisplays.area(width: 620, fit: iPhone8))
    }

    @Test("换不成：提示，屏还是原来的；下次加屏按新的建")
    func reshapeFails() async throws {
        let rig = try Rig()
        rig.displays.reshapeFails = true
        await rig.ready()
        rig.desk.setFit(iPhone8)
        await rig.desk.idle()
        #expect(rig.desk.state.notice == .reshapeFailed)
        #expect(rig.displays.fits[101] == .standard)
        rig.desk.setWanted(false)
        await rig.desk.idle()
        rig.desk.setWanted(true)
        await rig.desk.idle()
        #expect(rig.displays.fits[102] == iPhone8)
    }
}
