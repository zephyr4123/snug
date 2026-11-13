import Foundation
import Testing
@testable import SnugCore

@Suite("虚拟屏身份与布局模式匹配")
struct IdentityAndModeTests {
    @Test("稳定序列号：FNV-1a 32 位，key 为 名字|宽x高|高清，夹具按 PR #14 算法推算")
    func stableSerial() {
        #expect(VirtualDisplayIdentity.serial(for: DeviceProfile(name: "iPhone", kind: .phone, width: 2868, height: 1320)) == 2_757_468_297)
        #expect(VirtualDisplayIdentity.serial(for: DeviceProfile(name: "iPhone", kind: .phone, width: 2400, height: 1320)) == 2_361_386_375)
        // 同一配置每次都一样；改高清就是另一个身份
        let a = DeviceProfile(name: "iPad", kind: .tablet, width: 2360, height: 1640)
        var b = a
        b.hiDPI = false
        #expect(VirtualDisplayIdentity.serial(for: a) == VirtualDisplayIdentity.serial(for: a))
        #expect(VirtualDisplayIdentity.serial(for: a) != VirtualDisplayIdentity.serial(for: b))
    }

    @Test("序列号落在 1...0xFFFF_FFEF：取模后为 0 时取 1")
    func serialRange() {
        #expect(VirtualDisplayIdentity.fnv1a("") % 0xFFFF_FFF0 != 0)  // 空串的 FNV-1a 是偏移基数本身
        #expect(VirtualDisplayIdentity.serial(fromHash: 0) == 1)
        #expect(VirtualDisplayIdentity.serial(fromHash: 0xFFFF_FFF0) == 1)
        #expect(VirtualDisplayIdentity.serial(fromHash: 0xFFFF_FFF5) == 5)
    }

    @Test("虚拟屏名称、厂商号、产品号")
    func identity() {
        #expect(VirtualDisplayIdentity.name(for: iPhone) == "Snug · iPhone")
        #expect(VirtualDisplayIdentity.vendorID == 0x534E)
        #expect(VirtualDisplayIdentity.productID == 0x0001)
    }

    @Test("建屏请求只给一个模式：高清时是像素的一半")
    func singleMode() {
        let r = VirtualDisplayRequest(profile: iPhone)
        #expect(r.modeWidth == 1200 && r.modeHeight == 660)
        #expect(r.pixelWidth == 2400 && r.pixelHeight == 1320)
        var flat = iPhone
        flat.hiDPI = false
        #expect(VirtualDisplayRequest(profile: flat).modeWidth == 2400)
        #expect(r.serial == VirtualDisplayIdentity.serial(for: iPhone))
    }

    private let saved = DisplayModeInfo(ioDisplayModeID: 7, width: 1512, height: 982, pixelWidth: 3024, pixelHeight: 1964, refreshRate: 120)

    @Test("模式匹配：先比 ioDisplayModeID（尺寸也得对上），再比尺寸、像素、刷新率")
    func modeMatching() {
        let sameSizeOtherID = DisplayModeInfo(ioDisplayModeID: 9, width: 1512, height: 982, pixelWidth: 3024, pixelHeight: 1964, refreshRate: 120)
        let idOnly = DisplayModeInfo(ioDisplayModeID: 7, width: 1920, height: 1080, pixelWidth: 1920, pixelHeight: 1080, refreshRate: 60)
        let exact = saved
        let otherRate = DisplayModeInfo(ioDisplayModeID: 3, width: 1512, height: 982, pixelWidth: 3024, pixelHeight: 1964, refreshRate: 60)
        #expect(DisplayModeMatcher.bestMatch(for: saved, in: [sameSizeOtherID, exact]) == 1)
        #expect(DisplayModeMatcher.bestMatch(for: saved, in: [idOnly, otherRate, sameSizeOtherID]) == 2)
        #expect(DisplayModeMatcher.bestMatch(for: saved, in: [otherRate, idOnly]) == nil)
        // 刷新率允许 ±0.5 的误差（119.88 与 120）
        let ntsc = DisplayModeInfo(ioDisplayModeID: 4, width: 1512, height: 982, pixelWidth: 3024, pixelHeight: 1964, refreshRate: 119.88)
        #expect(DisplayModeMatcher.bestMatch(for: saved, in: [ntsc]) == 0)
    }

    @Test("当前模式已经对就跳过")
    func skipWhenSame() {
        #expect(DisplayModeMatcher.isSame(saved, as: saved))
        var other = saved
        other.pixelWidth = 1512
        #expect(!DisplayModeMatcher.isSame(other, as: saved))
    }
}
