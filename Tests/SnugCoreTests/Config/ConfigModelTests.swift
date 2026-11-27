import Foundation
import Testing
@testable import SnugCore

@Suite("配置 AppConfig")
struct ConfigModelTests {
    @Test("默认值：只有一块开着的竖屏手机屏（17 Pro Max），不改主屏；手势开着，截图键关着，字号默认放大 2 级，还没看过欢迎页，从腾讯云更新")
    func defaults() {
        let c = AppConfig()
        #expect(c.screens == [.legacyPhone(.standard, enabled: true)])
        #expect(c.mainScreen == nil)
        #expect(c.gestures)
        #expect(!c.screenshot)
        #expect(c.zoomSteps == 2)
        #expect(!c.welcomed)
        #expect(c.updateSource == .tencent)
        #expect(c.lastVersion == nil)
    }

    private func decode(_ json: String) throws -> AppConfig {
        try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
    }

    @Test("2.5 的配置迁成一块竖屏手机屏：名字、身份不变，开关沿用总开关，型号沿用（没写类别的都是手机）")
    func migratesLegacyPhone() throws {
        let c = try decode(#"{"phoneScreen":false,"phone":{"model":"华为 Mate 70 Pro","screen":{"width":1260,"height":2832}},"zoomSteps":3}"#)
        let phone = DeviceChoice(model: "华为 Mate 70 Pro", screen: DeviceScreen(width: 1260, height: 2832))
        #expect(c.screens == [.legacyPhone(phone, enabled: false)])
        #expect(c.screens[0].id == .phone)
        #expect(c.screens[0].name == "Snug 手机屏")
        #expect(c.screens[0].serials == [200_000_108, 200_000_118, 200_000_128])
        #expect(c.screens[0].device.kind == .phone)
        #expect(c.zoomSteps == 3)
        // 再早的配置连型号都没有：默认 17 Pro Max、开着
        #expect(try decode(#"{"zoomSteps":3}"#).screens == [.legacyPhone(.standard, enabled: true)])
    }

    @Test("旧配置的型号手改坏了（横着写、不是正数、缺字段）：迁成默认型号，不连累别的设置")
    func migratesBrokenPhone() throws {
        for bad in [#"{"width":2400,"height":1080}"#, #"{"width":0,"height":2400}"#, #"{"width":1080}"#] {
            let c = try decode(#"{"zoomSteps":3,"phone":{"screen":\#(bad)}}"#)
            #expect(c.screens == [.legacyPhone(.standard, enabled: true)])
            #expect(c.zoomSteps == 3)
        }
    }

    @Test("新版写出的配置：2.5 读得出该读的两项（取第一块竖屏手机屏），新字段原样读回")
    func writesLegacyFields() throws {
        var c = AppConfig()
        let tablet = DeviceChoice(model: "Apple iPad Pro 11 英寸（M5）", screen: DeviceScreen(width: 1668, height: 2420, points: 834), kind: .tablet)
        c.addScreen(orientation: .landscape, device: tablet)
        c.screens.swapAt(0, 1)
        c.screens[1].enabled = false
        c.screens[1].device = DeviceChoice(model: nil, screen: DeviceScreen(width: 1080, height: 2400))
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(c)) as? [String: Any]
        #expect(json?["phoneScreen"] as? Bool == false)
        let phone = try #require(json?["phone"] as? [String: Any])
        #expect((phone["screen"] as? [String: Int])?["width"] == 1080)
        #expect(try JSONDecoder().decode(AppConfig.self, from: JSONEncoder().encode(c)) == c)
    }

    @Test("没有竖屏手机屏时，旧字段写成关着的默认手机：降级回 2.5 不会凭空多出一块屏")
    func legacyFieldsWithoutPhone() throws {
        var c = AppConfig()
        c.removeScreen(.phone)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(c)) as? [String: Any]
        #expect(json?["phoneScreen"] as? Bool == false)
        #expect(try decode(String(decoding: JSONEncoder().encode(c), as: UTF8.self)).screens.isEmpty)
    }

    @Test("从旧版迁入的 iPad 仍可降级回读，单独新加的平板不会成为旧版的手机屏")
    func legacyTabletFields() throws {
        struct LegacyChoice: Decodable {
            let model: String?
            let screen: DeviceScreen
        }
        struct LegacyConfig: Decodable {
            let phoneScreen: Bool
            let phone: LegacyChoice
        }
        let tablet = DeviceChoice(model: "Apple iPad mini（第 6 代）", screen: DeviceScreen(width: 1488, height: 2266, points: 744), kind: .tablet)
        var config = AppConfig()
        config.screens[0].device = tablet
        let encoder = JSONEncoder(), decoder = JSONDecoder()
        let legacy = try decoder.decode(LegacyConfig.self, from: encoder.encode(config))
        #expect(legacy.phoneScreen)
        #expect(legacy.phone.model == tablet.model && legacy.phone.screen == tablet.screen)

        config.removeScreen(.phone)
        config.addScreen(orientation: .portrait, device: tablet)
        let added = try decoder.decode(LegacyConfig.self, from: encoder.encode(config))
        #expect(!added.phoneScreen)
        #expect(added.phone.model == DeviceChoice.standard.model)
    }

    @Test("加屏：序列号一段一段往后分，删掉的不回收；名字按型号和方向起")
    func addScreen() throws {
        var c = AppConfig()
        let ipad = DeviceChoice(model: "Apple iPad（A16）", screen: DeviceScreen(width: 1640, height: 2360, points: 820), kind: .tablet)
        let a = c.addScreen(orientation: .landscape, device: ipad, now: AppConfig.serialEpoch)!
        let b = c.addScreen(orientation: .landscape, device: .standard, now: AppConfig.serialEpoch)!
        #expect(a.serials == [200_100_000, 200_100_001, 200_100_002])
        #expect(b.serials == [200_100_010, 200_100_011, 200_100_012])
        #expect(a.name == "Snug iPad")
        #expect(b.name == "Snug iPhone 17 Pro Max 横屏")
        #expect(a.id != b.id)
        c.removeScreen(a.id)
        let d = c.addScreen(orientation: .portrait, device: .standard, name: "我的手机", now: AppConfig.serialEpoch)!
        #expect(d.serials.first == 200_100_020)
        #expect(d.name == "我的手机")
        #expect(c.screens.map(\.id) == [.phone, b.id, d.id])
    }

    @Test("同一设备两种方向：已有的屏可以直接用；就算列表已满，也可以启用关着的另一方向")
    func otherOrientation() {
        var c = AppConfig()
        let ipad = DeviceChoice(model: "Apple iPad mini（第 6 代）", screen: DeviceScreen(width: 1488, height: 2266, points: 744), kind: .tablet)
        let portrait = c.addScreen(orientation: .portrait, device: ipad)!
        let computer = c.addScreen(orientation: .landscape, device: DeviceChoice(model: nil, screen: ipad.screen, kind: .computer))!
        #expect(c.otherOrientation(for: portrait) == .add(.landscape))
        #expect(c.otherOrientation(for: computer) == nil)

        let landscape = c.addScreen(orientation: .landscape, device: ipad, name: "书桌")!
        #expect(c.otherOrientation(for: landscape) == .existing(portrait))
        #expect(c.otherOrientation(for: portrait) == .existing(landscape))
        #expect(c.otherOrientation(for: c.screens[0]) == .limitReached)
        c.screens[3].enabled = false
        #expect(c.otherOrientation(for: portrait) == .existing(c.screens[3]))
    }

    @Test("手动加过多块相同的横屏时，优先指向开着的那块")
    func prefersEnabledOrientation() {
        var c = AppConfig()
        let phone = c.screens[0]
        c.addScreen(orientation: .landscape, device: phone.device)
        c.screens[1].enabled = false
        let on = c.addScreen(orientation: .landscape, device: phone.device)!
        #expect(c.otherOrientation(for: phone) == .existing(on))
    }

    @Test("横屏自定义的宽高重新打开时按填写方向显示，转成竖屏时共用同一份设备尺寸")
    func orientedCustomDimensions() throws {
        let screen = try #require(DeviceScreen.custom(2266, 1488))
        #expect(screen.dimensions(in: .landscape) == (2266, 1488))
        #expect(screen.dimensions(in: .portrait) == (1488, 2266))
    }

    @Test("降级到 2.5 跑过再升级回来（屏幕列表和计数器都被 2.5 写盘丢掉）：新屏的号按时间往后排，不复用以前分过的")
    func serialsSurviveLostCounter() {
        let earlier = AppConfig.serialEpoch.addingTimeInterval(100 * 60)
        var before = AppConfig()
        let old = before.addScreen(orientation: .landscape, device: .standard, now: earlier)!
        var lost = AppConfig()
        let new = lost.addScreen(orientation: .landscape, device: .standard, now: earlier.addingTimeInterval(60))!
        #expect(old.serials.first == 200_101_000)
        #expect(new.serials.first == 200_101_010)
        #expect(Set(old.serials).isDisjoint(with: new.serials))
    }

    @Test("手改出离谱的号段计数（大到序列号装不下）：夹回上限，加屏不崩")
    func hugeSerialBlock() throws {
        var c = try decode(#"{"nextSerialBlock":99999999999}"#)
        #expect(c.nextSerialBlock == AppConfig.maxSerialBlock)
        let added = c.addScreen(orientation: .portrait, device: .standard)!
        #expect(added.serials.allSatisfy { $0 >= AppConfig.serialBase })
    }

    @Test("删掉设为主屏的那块：主屏回到「不改」")
    func removeMainScreen() {
        var c = AppConfig()
        c.mainScreen = .phone
        c.removeScreen(.phone)
        #expect(c.mainScreen == nil)
    }

    @Test("手改坏了的屏幕列表：分辨率不对、没有序列号、id 重复的那一项丢掉；主屏指向没有的屏当作不改")
    func sanitizesScreens() throws {
        let good = #"{"id":"a","orientation":"landscape","device":{"screen":{"width":1080,"height":1920},"kind":"computer"},"enabled":true,"name":"A","serials":[1,2,3]}"#
        let badSize = #"{"id":"b","orientation":"landscape","device":{"screen":{"width":1920,"height":1080}},"enabled":true,"name":"B","serials":[4]}"#
        let noSerial = #"{"id":"c","orientation":"portrait","device":{"screen":{"width":9,"height":20}},"enabled":true,"name":"C","serials":[]}"#
        let c = try decode(#"{"screens":[\#(good),\#(badSize),\#(noSerial),\#(good)],"mainScreen":"zzz","nextSerialBlock":5}"#)
        #expect(c.screens.map(\.id.rawValue) == ["a"])
        #expect(c.screens[0].device.kind == .computer)
        #expect(c.mainScreen == nil)
        #expect(c.nextSerialBlock == 5)
    }

    @Test("屏幕列表里有一项结构坏了（取值不认识、缺字段）：只丢那一项，其余几块和主屏照旧，不当成 2.5 的配置迁移")
    func dropsUndecodableScreen() throws {
        let good = #"{"id":"a","orientation":"landscape","device":{"screen":{"width":1080,"height":1920},"kind":"computer"},"enabled":true,"name":"A","serials":[1,2,3]}"#
        let badOrientation = #"{"id":"b","orientation":"Landscape","device":{"screen":{"width":9,"height":20}},"enabled":true,"name":"B","serials":[4]}"#
        let noName = #"{"id":"c","orientation":"portrait","device":{"screen":{"width":9,"height":20}},"enabled":true,"serials":[5]}"#
        let c = try decode(#"{"screens":[\#(badOrientation),\#(good),\#(noName)],"mainScreen":"a","phoneScreen":true}"#)
        #expect(c.screens.map(\.id.rawValue) == ["a"])
        #expect(c.mainScreen == ScreenID("a"))
    }

    @Test("屏幕列表这一项根本不是列表：整份按损坏处理（交给 ConfigStore 隔离原文件），不静默迁成一块手机屏")
    func screensNotAList() {
        #expect(throws: DecodingError.self) { try decode(#"{"screens":{"id":"a"},"phoneScreen":true}"#) }
    }

    @Test("不认识的更新源（比如更新的版本写的）用默认值，不把整份配置判为损坏")
    func unknownUpdateSource() throws {
        let c = try JSONDecoder().decode(AppConfig.self, from: Data(#"{"updateSource":"mirror","zoomSteps":3}"#.utf8))
        #expect(c.updateSource == .tencent)
        #expect(c.zoomSteps == 3)
    }

    @Test("缺字段的 config.json 用默认值补齐；旧版留下的字段忽略，而不是整份判为损坏")
    func decodeMissingAndLegacyKeys() throws {
        let json = #"{"gestures":false,"devices":[{"name":"iPad"}],"keepOnlyVirtual":true}"#
        let c = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        #expect(c.gestures == false)
        #expect(c.screens == [.legacyPhone(.standard, enabled: true)])
        #expect(!c.screenshot)
        #expect(c.zoomSteps == 2)
    }

    @Test("手改出界的字号级数夹回 0...4")
    func clampsZoomSteps() throws {
        let high = try JSONDecoder().decode(AppConfig.self, from: Data(#"{"zoomSteps":9}"#.utf8))
        let low = try JSONDecoder().decode(AppConfig.self, from: Data(#"{"zoomSteps":-3}"#.utf8))
        #expect(high.zoomSteps == 4)
        #expect(low.zoomSteps == 0)
    }

    @Test("分辨率：没调过的不写进配置（旧版读到的和以前一样），调过的原样读回；旧配置没有这一项读成默认")
    func baseWidth() throws {
        var c = AppConfig()
        c.screens[0].baseWidth = 660
        let data = try JSONEncoder().encode(c)
        #expect(try JSONDecoder().decode(AppConfig.self, from: data).screens[0].baseWidth == 660)
        c.screens[0].baseWidth = nil
        #expect(!String(decoding: try JSONEncoder().encode(c), as: UTF8.self).contains("baseWidth"))
        let old = try decode(#"{"screens":[{"id":"phone","orientation":"portrait","device":{"model":"Apple iPhone 17 Pro Max","screen":{"width":1320,"height":2868,"points":440},"kind":"phone"},"enabled":true,"name":"Snug 手机屏","serials":[200000108]}]}"#)
        #expect(old.screens[0].baseWidth == nil)
    }

    @Test("换型号：分辨率回到默认（范围和最清晰那一格都跟着型号变）")
    func changingDeviceResetsResolution() {
        var screen = ScreenConfig.legacyPhone(.standard, enabled: true)
        screen.baseWidth = 660
        let other = DeviceChoice(model: "华为 Mate 70 Pro", screen: DeviceScreen(width: 1260, height: 2832))
        screen.setDevice(other)
        #expect(screen.device == other)
        #expect(screen.baseWidth == nil)
    }

    @Test("编码再解码保持不变")
    func roundTrip() throws {
        var c = AppConfig()
        c.screens[0].enabled = false
        c.mainScreen = .phone
        c.screenshot = true
        c.zoomSteps = 3
        c.welcomed = true
        c.updateSource = .github
        c.lastVersion = Version(major: 2, minor: 1, patch: 0)
        c.screens[0].device = DeviceChoice(model: "华为 Mate 70 Pro", screen: DeviceScreen(width: 1260, height: 2832))
        c.addScreen(orientation: .landscape, device: DeviceChoice(model: nil, screen: DeviceScreen(width: 1600, height: 2560, notch: 30), kind: .computer))
        #expect(try JSONDecoder().decode(AppConfig.self, from: JSONEncoder().encode(c)) == c)
    }

    @Test("2.6.2 及以前的「设为主屏」只在远程时生效：升到常驻的版本时撤掉，要在设置里看过确认框重新选；同版本、开发版、新装、没设过的不动")
    func dropsRemoteOnlyMain() {
        let v262 = Version(major: 2, minor: 6, patch: 2)
        let v270 = Version(major: 2, minor: 7, patch: 0)
        var c = AppConfig()
        c.mainScreen = .phone
        c.lastVersion = v262
        var upgraded = c
        #expect(upgraded.dropRemoteOnlyMain(running: v270) == .phone)
        #expect(upgraded.mainScreen == nil)
        // 开发中的版本号还没升（照旧 2.6.2）：不撤，不然本机自测每次启动都被清掉
        var dev = c
        #expect(dev.dropRemoteOnlyMain(running: v262) == nil)
        #expect(dev.mainScreen == .phone)
        // 已经在常驻的版本上设的
        var current = c
        current.lastVersion = v270
        #expect(current.dropRemoteOnlyMain(running: Version(major: 2, minor: 7, patch: 1)) == nil)
        #expect(current.mainScreen == .phone)
        // 新装（没记过版本）、没设过主屏
        var fresh = c
        fresh.lastVersion = nil
        #expect(fresh.dropRemoteOnlyMain(running: v270) == nil)
        var none = AppConfig()
        none.lastVersion = v262
        #expect(none.dropRemoteOnlyMain(running: v270) == nil)
    }
}
