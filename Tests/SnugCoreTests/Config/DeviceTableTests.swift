import Foundation
import Testing
@testable import SnugCore

@Suite("设备表：类型预填、按行校验、从 UU 导入")
struct DeviceTableTests {
    @Test("类型预填：UU「电脑」组 → 电脑；名字含 pad（不分大小写）→ 平板；其余 → 手机")
    func guessKind() {
        #expect(DeviceKind.guess(name: "iPad Air", isComputerGroup: true) == .computer)
        #expect(DeviceKind.guess(name: "iPad Air", isComputerGroup: false) == .tablet)
        #expect(DeviceKind.guess(name: "OPPO Pad 3 Pro", isComputerGroup: false) == .tablet)
        #expect(DeviceKind.guess(name: "iPhone 17", isComputerGroup: false) == .phone)
    }

    @Test("按行校验：电脑不管尺寸；两项都空算「还没填」不报错；只填一项、超出 320...16384 才报错")
    func rowIssues() {
        func row(_ kind: DeviceKind, _ w: Int, _ h: Int) -> DeviceProfile {
            DeviceProfile(name: "X", kind: kind, width: w, height: h)
        }
        #expect(row(.computer, 5, 0).sizeIssue == nil)
        #expect(row(.phone, 0, 0).sizeIssue == nil)
        #expect(row(.phone, 2868, 1320).sizeIssue == nil)
        #expect(row(.phone, 320, 16384).sizeIssue == nil)
        #expect(row(.phone, 2868, 0).sizeIssue == .incomplete)
        #expect(row(.tablet, 0, 1640).sizeIssue == .incomplete)
        #expect(row(.phone, 319, 1320).sizeIssue == .outOfRange)
        #expect(row(.phone, 2868, 16385).sizeIssue == .outOfRange)
    }

    @Test("按行保存（修 B10）：无效行不写入、不连累别的行；有效行只替换同名那一行")
    func replaceDevice() throws {
        var c = AppConfig()
        c.devices = [DeviceProfile(name: "iPad", kind: .tablet, width: 2360, height: 1640),
                     DeviceProfile(name: "iPhone", kind: .phone, width: 0, height: 0)]

        var bad = c.devices[1]
        bad.width = 2868   // 只填了宽
        #expect(throws: DeviceSizeIssue.incomplete) { try c.replaceDevice(bad) }
        #expect(c.devices[1].width == 0)
        #expect(c.devices[0].width == 2360)

        var good = c.devices[0]
        good.hiDPI = false
        try c.replaceDevice(good)
        #expect(c.devices[0].hiDPI == false)
        #expect(c.devices[1] == DeviceProfile(name: "iPhone", kind: .phone, width: 0, height: 0))
    }

    @Test("替换一个不在列表里的设备：报错，不悄悄追加")
    func replaceUnknown() {
        var c = AppConfig()
        #expect(throws: DeviceTableError.unknownDevice("Nope")) {
            try c.replaceDevice(DeviceProfile(name: "Nope", kind: .phone, width: 0, height: 0))
        }
    }

    @Test("从 UU 导入：按 UU 的顺序，排除本机，已有设置保留，新设备按名字预填类型、尺寸留空，UU 里没有了的删掉")
    func importMerge() {
        let saved = [DeviceProfile(name: "iPhone", kind: .phone, width: 2868, height: 1320, hiDPI: false),
                     DeviceProfile(name: "旧手机", kind: .phone, width: 1000, height: 500)]
        let found = [UUDevice(name: "MacBook", isComputerGroup: true, isSelf: true, platform: "macos"),
                     UUDevice(name: "OPPO Pad 3", isComputerGroup: false, isSelf: false, platform: "android"),
                     UUDevice(name: "iPhone", isComputerGroup: false, isSelf: false, platform: "ios"),
                     UUDevice(name: "Win 台式机", isComputerGroup: true, isSelf: false, platform: "windows")]
        let merged = DeviceImport.merge(found: found, saved: saved)
        #expect(merged.map(\.name) == ["OPPO Pad 3", "iPhone", "Win 台式机"])
        #expect(merged[0] == DeviceProfile(name: "OPPO Pad 3", kind: .tablet, width: 0, height: 0,
                                           uuComputer: false, platform: "android"))
        #expect(merged[1] == DeviceProfile(name: "iPhone", kind: .phone, width: 2868, height: 1320, hiDPI: false,
                                           uuComputer: false, platform: "ios"))
        #expect(merged[2].kind == .computer)
        #expect(merged[2].uuComputer == true)
    }
}
