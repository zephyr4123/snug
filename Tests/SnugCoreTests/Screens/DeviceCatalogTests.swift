import Foundation
import Testing
@testable import SnugCore

@Suite("机型库 DeviceCatalog")
struct DeviceCatalogTests {
    /// 随 App 发的机型库（唯一的数据源）
    static let bundled = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Assets/device-models.json")

    private func catalog(_ json: String) throws -> DeviceCatalog {
        try DeviceCatalog(json: Data(json.utf8))
    }

    private let sample = """
    {"phone": [
      {"name": "Apple", "models": [
        {"name": "iPhone 17 Pro Max", "year": 2025, "screen": [1320, 2868], "points": 440},
        {"name": "iPhone 17", "year": 2025, "screen": [1206, 2622], "points": 402}
      ]},
      {"name": "华为", "aliases": ["HUAWEI"], "models": [
        {"name": "Mate 70 Pro", "year": 2024, "screen": [1260, 2832]}
      ]}
    ],
    "tablet": [
      {"name": "Apple", "models": [{"name": "iPad（A16）", "year": 2025, "screen": [1640, 2360], "points": 820}]}
    ],
    "computer": [
      {"name": "Apple", "models": [{"name": "MacBook Air 13 英寸（M4）", "year": 2025, "screen": [956, 1470], "notch": 33}]}
    ]}
    """

    @Test("解码：按手机、平板、电脑三段，品牌和机型按文件里的顺序；全名是品牌 + 型号，类别跟着段走")
    func decode() throws {
        let c = try catalog(sample)
        #expect(c.brands.map(\.id) == ["phone/Apple", "phone/华为", "tablet/Apple", "computer/Apple"])
        #expect(c.models.map(\.id) == ["Apple iPhone 17 Pro Max", "Apple iPhone 17", "华为 Mate 70 Pro",
                                       "Apple iPad（A16）", "Apple MacBook Air 13 英寸（M4）"])
        #expect(c.model(id: "Apple iPhone 17")?.screen == DeviceScreen(width: 1206, height: 2622, points: 402))
        #expect(c.model(id: "华为 Mate 70 Pro")?.screen.points == nil)
        #expect(c.model(id: "Apple iPad（A16）")?.kind == .tablet)
        #expect(c.model(id: "Apple MacBook Air 13 英寸（M4）")?.screen.notch == 33)
        #expect(c.brands(in: [.computer]).map(\.name) == ["Apple"])
        // 只有手机一段的也行
        #expect(try catalog(#"{"phone":[{"name":"A","models":[{"name":"X","screen":[1080,2400]}]}]}"#).models.count == 1)
    }

    @Test("不合格的整份拒收，写明是哪一条：横着写、型号重复、品牌重复、screen 不是两个数、没有机型")
    func rejects() {
        let bad = [
            #"{"phone":[{"name":"A","models":[{"name":"X","year":2024,"screen":[2400,1080]}]}]}"#,
            #"{"phone":[{"name":"A","models":[{"name":"X","year":2024,"screen":[1080,2400]},{"name":"x ","year":2024,"screen":[1080,2400]}]}]}"#,
            #"{"phone":[{"name":"A","models":[{"name":"X","year":2024,"screen":[1080]}]}]}"#,
            #"{"phone":[{"name":"A","models":[{"name":"X","screen":[1080,2400]}]},{"name":"a","models":[{"name":"Y","screen":[1080,2400]}]}]}"#,
            #"{"phone":[{"name":"A","models":[]}]}"#,
            #"{"phone":[{"name":"A","models":[{"name":"X","year":2024,"screen":[0,2400]}]}]}"#,
            #"{"phone":[{"name":"A","models":[{"name":"X","legacyNames":["Y"],"screen":[1,2]},{"name":"y","screen":[1,2]}]}]}"#,
            #"{"phone":[{"name":"A","models":[{"name":"X","legacyNames":[""],"screen":[1,2]}]}]}"#,
            "不是 JSON",
        ]
        for json in bad {
            #expect(throws: DeviceCatalogError.self) { try catalog(json) }
        }
    }

    @Test("搜索：不分大小写、不看空格，型号、品牌、别名都能搜；品牌整个命中列出全部；搜不到是空")
    func search() throws {
        let c = try catalog(sample)
        #expect(c.search("17promax").flatMap(\.models).map(\.name) == ["iPhone 17 Pro Max"])
        #expect(c.search(" IPHONE 17 ").flatMap(\.models).count == 2)
        #expect(c.search("huawei mate").flatMap(\.models).map(\.name) == ["Mate 70 Pro"])
        #expect(c.search("华为").flatMap(\.models).count == 1)
        #expect(c.search("").map(\.id) == ["phone/Apple", "phone/华为", "tablet/Apple", "computer/Apple"])
        #expect(c.search("pixel").isEmpty)
        // 按类别筛：竖屏只列手机和平板
        #expect(c.search("", in: [.phone, .tablet]).map(\.id) == ["phone/Apple", "phone/华为", "tablet/Apple"])
        #expect(c.search("apple", in: [.computer]).flatMap(\.models).map(\.name) == ["MacBook Air 13 英寸（M4）"])
    }

    @Test("同一个品牌在不同的段里可以各有一段；同一段里重了不行")
    func brandsPerKind() {
        #expect(throws: DeviceCatalogError.self) {
            try catalog(#"{"phone":[{"name":"A","models":[{"name":"X","screen":[1,2]}]},{"name":"a","models":[{"name":"Y","screen":[1,2]}]}]}"#)
        }
        #expect(throws: Never.self) {
            try catalog(#"{"phone":[{"name":"A","models":[{"name":"X","screen":[1,2]}]}],"tablet":[{"name":"A","models":[{"name":"Y","screen":[1,2]}]}]}"#)
        }
    }

    @Test("自己填的：横着填的按竖握换过来，比例也行；没填、不是正数、大得离谱的不收")
    func custom() {
        #expect(DeviceScreen.custom(1080, 2400) == DeviceScreen(width: 1080, height: 2400))
        #expect(DeviceScreen.custom(2400, 1080) == DeviceScreen(width: 1080, height: 2400))
        #expect(DeviceScreen.custom(9, 20) == DeviceScreen(width: 9, height: 20))
        for (a, b) in [(nil, 2400), (1080, nil), (0, 2400), (-1, 2400), (1080, 99999)] as [(Int?, Int?)] {
            #expect(DeviceScreen.custom(a, b) == nil)
        }
    }

    @Test("随 App 发的机型库：读得出来，三类都有；#20 要的摩托罗拉、联想系都在")
    func bundledLoads() throws {
        let c = try DeviceCatalog(contentsOf: Self.bundled)
        #expect(c.brands(in: [.phone]).count >= 10)
        #expect(c.brands(in: [.phone]).flatMap(\.models).count >= 100)
        #expect(c.brands(in: [.tablet]).flatMap(\.models).count >= 20)
        #expect(c.brands(in: [.computer]).flatMap(\.models).count >= 10)
        #expect(!c.search("motorola", in: [.phone]).isEmpty)
        #expect(!c.search("拯救者", in: [.phone]).isEmpty)
        #expect(!c.search("拯救者", in: [.tablet]).isEmpty)
    }

    @Test("随 App 发的机型库：平板只在平板段（手机段里的平板会按手机扣掉上下，iPad 上实测铺满、不用扣）")
    func bundledTabletsOnlyInTabletSection() throws {
        let c = try DeviceCatalog(contentsOf: Self.bundled)
        let tabletWords = ["iPad", "Pad", "Tab", "平板"]
        for model in c.brands(in: [.phone]).flatMap(\.models) {
            #expect(!tabletWords.contains { model.name.contains($0) }, "\(model.id)")
        }
        #expect(c.search("ipad", in: [.tablet]).flatMap(\.models).count >= 20)
    }

    @Test("随 App 发的机型库：每一条、每个方向（手机平板竖横、电脑横）、每一档都过 2 倍门槛、在像素上限里；登记的第一档不比上限小太多")
    func bundledFits() throws {
        let c = try DeviceCatalog(contentsOf: Self.bundled)
        for model in c.models {
            for orientation in model.kind == .computer ? [Orientation.landscape] : Orientation.allCases {
                let fit = ScreenFit(device: model.screen, kind: model.kind, orientation: orientation)
                let cap = orientation == .portrait ? ScreenFit.portraitPixels : ScreenFit.landscapePixels
                for width in fit.widths {
                    let size = fit.size(width: width)
                    let label = "\(model.id) \(orientation) \(width) 宽"
                    #expect(max(size.width, size.height) >= 800 && min(size.width, size.height) >= 525, "\(label)")
                    #expect(size.width * 2 <= cap.width && size.height * 2 <= cap.height, "\(label)")
                }
                // 第一档的 2 倍高至少是像素上限高的三分之一，不然屏不上线（实测 1120 / 3840 上线、1050 / 3840 不上线）
                let first = try #require(fit.registrationOrder.first)
                #expect(fit.size(width: first).height * 2 >= cap.height / 3, "\(model.id) \(orientation)")
            }
        }
    }

    @Test("默认的那台（DeviceChoice.standard）就是机型库里的一条，数值一致")
    func standardIsInCatalog() throws {
        let c = try DeviceCatalog(contentsOf: Self.bundled)
        let standard = try #require(DeviceChoice.standard.model)
        #expect(c.model(id: standard)?.screen == DeviceChoice.standard.screen)
    }

    @Test("机型库里 Apple 的手机、平板都有逻辑宽度（比例按它算才准）；电脑写的就是点，不带 points")
    func bundledApplePoints() throws {
        let c = try DeviceCatalog(contentsOf: Self.bundled)
        for model in c.models where model.brand == "Apple" {
            #expect((model.screen.points != nil) == (model.kind != .computer), "\(model.id)")
        }
    }

    @Test("配置里的那台按机型库现在的数值来：数值改了跟着改，改名删了用存下的，自己填的不动")
    func resolve() throws {
        let c = try catalog(sample)
        let stale = DeviceChoice(model: "华为 Mate 70 Pro", screen: DeviceScreen(width: 1200, height: 2700))
        #expect(c.resolve(stale).screen == DeviceScreen(width: 1260, height: 2832))
        let gone = DeviceChoice(model: "华为 Mate 60", screen: DeviceScreen(width: 1260, height: 2720))
        #expect(c.resolve(gone) == gone)
        let custom = DeviceChoice(model: nil, screen: DeviceScreen(width: 9, height: 20))
        #expect(c.resolve(custom) == custom)
    }

    @Test("2.5 的 iPad mini 6 和新版存成手机的旧型号按平板尺寸建屏")
    func legacyIPadFit() throws {
        let device = #""model":"Apple iPad mini (6th generation)","screen":{"width":1488,"height":2266,"points":744}"#
        let portrait = #"{"phone":{\#(device)}}"#
        let landscape = """
        {"screens":[{"id":"ipad","name":"iPad","enabled":true,"orientation":"landscape","serials":[12],
                     "device":{"kind":"phone",\(device)}}]}
        """
        let catalog = try DeviceCatalog(contentsOf: Self.bundled)
        for (json, size) in [(portrait, CGSize(width: 600, height: 914)), (landscape, CGSize(width: 914, height: 600))] {
            let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
            var screen = try #require(config.screens.first)
            screen.device = catalog.resolve(screen.device)
            #expect(screen.device.model == "Apple iPad mini（第 6 代）")
            #expect(screen.device.kind == .tablet)
            let fit = ScreenPlan.fit(of: screen)
            #expect(fit.size(width: fit.baseWidth) == size)
        }
    }

    @Test("旧 iPad 按型号对回机型库，同分辨率的其他型号和自定义尺寸各自保留")
    func resolvesIPadsByName() throws {
        let catalog = try DeviceCatalog(contentsOf: Self.bundled)
        let screen = DeviceScreen(width: 1488, height: 2266, points: 744)
        let newer = DeviceChoice(model: "Apple iPad mini (A17 Pro)", screen: screen)
        #expect(catalog.resolve(newer).model == "Apple iPad mini（A17 Pro）")
        let unknown = DeviceChoice(model: "Apple iPad mini (unknown)", screen: screen)
        let custom = DeviceChoice(model: nil, screen: screen)
        #expect(catalog.resolve(unknown) == unknown)
        #expect(catalog.resolve(custom) == custom)
    }
}

@Suite("设备类别 DeviceKind")
struct DeviceKindTests {
    @Test("触屏的是手机、平板，电脑不是（ScreenPlan.behavior 按它给行为）")
    func isTouch() {
        #expect(DeviceKind.allCases.filter(\.isTouch) == [.phone, .tablet])
    }

    @Test("平常的方向：手机竖，平板、电脑横；能选的方向：手机、平板横竖都行，电脑只能横；平常的方向总在能选的里面")
    func orientations() {
        #expect(DeviceKind.allCases.map(\.usualOrientation) == [.portrait, .landscape, .landscape])
        #expect(DeviceKind.phone.allowedOrientations == [.portrait, .landscape])
        #expect(DeviceKind.tablet.allowedOrientations == [.portrait, .landscape])
        #expect(DeviceKind.computer.allowedOrientations == [.landscape])
        for kind in DeviceKind.allCases {
            #expect(kind.allowedOrientations.contains(kind.usualOrientation), "\(kind)")
        }
    }

    @Test("型号能换成哪几类：触屏之间互换，电脑只换电脑")
    func swappableKinds() {
        #expect(DeviceKind.phone.swappableKinds == [.phone, .tablet])
        #expect(DeviceKind.tablet.swappableKinds == [.phone, .tablet])
        #expect(DeviceKind.computer.swappableKinds == [.computer])
    }
}
