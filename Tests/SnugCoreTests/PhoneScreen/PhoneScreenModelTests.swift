import CoreGraphics
import Foundation
import Testing
@testable import SnugCore

@Suite("手机屏的规格")
struct PhoneScreenSpecTests {
    @Test("竖屏 540x950、横屏 976x540，短边都是 540（2 倍高清的门槛），像素正好 2 倍")
    func sizes() {
        let portrait = PhoneScreenSpec(.portrait), landscape = PhoneScreenSpec(.landscape)
        #expect((portrait.width, portrait.height) == (540, 950))
        #expect((landscape.width, landscape.height) == (976, 540))
        #expect(min(portrait.width, portrait.height) == 540)
        #expect(min(landscape.width, landscape.height) == 540)
        #expect((portrait.pixelWidth, portrait.pixelHeight) == (1080, 1900))
    }

    @Test("物理尺寸按 220ppi 折算（不是手机的 460ppi）")
    func millimeters() {
        let mm = PhoneScreenSpec(.portrait).millimeters
        #expect(abs(mm.width - 1080.0 / 220 * 25.4) < 0.001)
        #expect(abs(mm.height - 1900.0 / 220 * 25.4) < 0.001)
    }

    @Test("每个方向一个固定身份，外加两个备用；两个方向互不重复")
    func serials() {
        let p = PhoneScreenSpec(.portrait).serials, l = PhoneScreenSpec(.landscape).serials
        #expect(p.first == 200_000_008)
        #expect(l.first == 200_000_007)
        #expect(p.count == 3 && l.count == 3)
        #expect(Set(p).isDisjoint(with: l))
    }
}

@Suite("控制端类型")
struct ControllerKindTests {
    @Test("手机、平板加手机屏")
    func mobile() {
        for name in ["iPhone 17 Pro Max", "张三的iPhone", "iPad Air", "OPPO Pad 3", "HUAWEI MatePad Pro", "Android 设备", "我的手机", "华为平板"] {
            #expect(ControllerKind(name: name) == .mobile, "\(name)")
        }
    }

    @Test("电脑不加")
    func computer() {
        for name in ["MacBook Air", "张三的Mac mini", "iMac", "DESKTOP-7Q2K1LM", "LAPTOP-AB12", "ThinkPad-X1", "办公室电脑", "Windows 11"] {
            #expect(ControllerKind(name: name) == .computer, "\(name)")
            #expect(!ControllerKind(name: name).wantsPhoneScreen)
        }
    }

    @Test("读不到名字或认不出：按手机处理，照样加手机屏")
    func unknownGetsScreen() {
        #expect(ControllerKind(name: nil) == .unknown)
        #expect(ControllerKind(name: "") == .unknown)
        #expect(ControllerKind(name: "Xiaomi 15") == .unknown)
        #expect(ControllerKind(name: nil).wantsPhoneScreen)
        #expect(ControllerKind(name: "Xiaomi 15").wantsPhoneScreen)
    }
}

@Suite("窗口列表")
struct WindowListTests {
    private func w(_ id: UInt32, _ app: String, bundle: String? = nil) -> WindowInfo {
        WindowInfo(key: WindowKey(pid: 1, id: id), app: app, bundleID: bundle, title: "")
    }

    @Test("按前后层次排，最近用过的在前；不在屏上的排最后、保持原顺序")
    func ordered() {
        let list = [w(1, "A"), w(2, "B"), w(3, "C"), w(4, "D")]
        #expect(WindowList.ordered(list, frontToBack: [3, 1]).map(\.key.id) == [3, 1, 2, 4])
    }

    @Test("UU远程 自己的窗口不出现")
    func excludesUU() {
        let list = [w(1, "UU远程", bundle: "com.netease.uuremote"), w(2, "Ghostty", bundle: "com.mitchellh.ghostty")]
        #expect(WindowList.ordered(list, frontToBack: [1, 2]).map(\.app) == ["Ghostty"])
    }

    @Test("日志标签：有标题带标题，太长截断")
    func label() {
        #expect(w(1, "Finder").label == "Finder")
        let long = WindowInfo(key: WindowKey(pid: 1, id: 1), app: "Safari", bundleID: nil, title: String(repeating: "长", count: 40))
        #expect(long.label == "Safari「\(String(repeating: "长", count: 30))」")
    }

    @Test("框对比：2 点以内算对上")
    func matches() {
        let a = CGRect(x: 0, y: 25, width: 540, height: 897)
        #expect(a.matches(CGRect(x: 1, y: 26, width: 541, height: 896)))
        #expect(!a.matches(CGRect(x: 0, y: 25, width: 540, height: 870)))
    }
}

@Suite("字号账本 ZoomBook")
struct ZoomBookTests {
    @Test("名单里的 App 按记住的级数，没记过用默认；名单外一律 0（不乱发 ⌘=）")
    func steps() {
        var book = ZoomBook()
        #expect(book.steps(for: "com.mitchellh.ghostty", default: 2) == 2)
        book.remember(3, for: "com.mitchellh.ghostty")
        #expect(book.steps(for: "com.mitchellh.ghostty", default: 2) == 3)
        #expect(book.steps(for: "com.apple.finder", default: 2) == 0)
        #expect(book.steps(for: nil, default: 2) == 0)
    }

    @Test("级数夹在 -4...8")
    func clamped() {
        var book = ZoomBook()
        book.remember(20, for: "com.apple.Safari")
        #expect(book.steps(for: "com.apple.Safari", default: 0) == 8)
        #expect(book.steps(for: "com.apple.Terminal", default: -9) == -4)
    }

    @Test("编码后能读回")
    func roundTrip() throws {
        var book = ZoomBook()
        book.remember(1, for: "dev.zed.Zed")
        #expect(try JSONDecoder().decode(ZoomBook.self, from: JSONEncoder().encode(book)) == book)
    }
}
