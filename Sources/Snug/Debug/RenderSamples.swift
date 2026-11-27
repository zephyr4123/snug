// --render-* 用的样例状态。窗口标题和设备名都是通用的，不带任何个人信息
import SwiftUI
import SnugCore

@MainActor
struct RenderSample {
    let name: String
    var dark = false
    /// nil：按内容自适应
    var size: CGSize?
    /// 挂进窗口再画（有 List 的界面要，见 Renderer.snapshot）
    var inWindow = false
    let view: () -> AnyView
}

@MainActor
enum RenderSamples {
    private static let stub = RenderStub()

    static func samples(for target: RenderTarget) -> [RenderSample] {
        switch target {
        case .settings: settings
        case .welcome: welcome
        case .about: about
        case .legacy: [RenderSample(name: "legacy") { AnyView(LegacyNoticeView(quitLegacy: {}, keepBoth: {})) }]
        case .menu: menu
        case .screens: screens
        case .library: library
        case .update: update
        }
    }

    // MARK: 样例的屏幕列表

    static let ipad = DeviceChoice(model: "Apple iPad（第 10 代）", screen: DeviceScreen(width: 1640, height: 2360, points: 820), kind: .tablet)
    static let air = DeviceChoice(model: "Apple MacBook Air 13 英寸（M4）", screen: DeviceScreen(width: 956, height: 1470, notch: 33), kind: .computer)
    static let tabletID = ScreenID("ipad")
    static let computerID = ScreenID("air")
    static let landscapeID = ScreenID("phone-landscape")
    static let tabletPortraitID = ScreenID("ipad-portrait")

    /// 每种屏各一块：原型上的手机竖屏（开）、iPad 横屏（开）、MacBook Air（关），再加横屏手机、竖屏 iPad 给屏上的面板用
    private static let allScreens = [
        ScreenConfig.legacyPhone(.standard, enabled: true),
        ScreenConfig(id: tabletID, orientation: .landscape, device: ipad, name: "Snug iPad", serials: [1]),
        ScreenConfig(id: computerID, orientation: .landscape, device: air, enabled: false, name: "Snug MacBook Air", serials: [2]),
        ScreenConfig(id: landscapeID, orientation: .landscape, device: .standard, enabled: false, name: "Snug iPhone 17 Pro Max 横屏", serials: [3]),
        ScreenConfig(id: tabletPortraitID, orientation: .portrait, device: ipad, enabled: false, name: "Snug iPad 竖屏", serials: [4]),
    ]

    /// 设置窗口用前三块（同原型）；trouble 那张用满 4 块，看「添加屏幕…」变灰
    private static func sampleConfig(count: Int = 3) -> AppConfig {
        var c = AppConfig()
        c.screens = Array(allScreens.prefix(min(count, ScreenConfig.limit)))
        return c
    }

    private static func sampleState() -> AppState {
        let s = AppState()
        s.accessibilityTrusted = true
        s.launchAtLogin = true
        s.devices = devices
        s.config = sampleConfig()
        s.remotes = Remotes.all.map(\.identity)
        return s
    }

    /// 登记的远控里只在启动时认屏的那几家（「提前准备虚拟屏」按它们显示）
    private static var launchOnlyRemotes: [String] {
        Remotes.all.map(\.identity).filter(\.seesScreensOnlyAtLaunch).map(\.displayName)
    }

    /// 远程中，开着的屏都建好了；手机在看第一块屏
    private static func connected(_ s: AppState) {
        s.connection = .connected
        s.remoteName = Remotes.all.first?.identity.displayName
        s.controllers = ["iPhone 17 Pro Max"]
        for (i, screen) in s.config.screens.enumerated() {
            var desk = Desk.State()
            desk.screen = .ready(DisplayID(20 + i))
            s.desks.desks[screen.id] = desk
        }
        s.streamedDisplay = 20
    }

    // MARK: 设置

    private static var settings: [RenderSample] {
        [
            page("settings-screens-idle") { _ in },
            page("settings-screens-remote") { s in connected(s) },
            page("settings-screens-remote-dark", dark: true) { s in
                connected(s)
                s.desks.desks[.phone]?.placed = Desk.Placed(window: windows[0], zoom: 2)
            },
            page("settings-screens-main") { s in s.config.mainScreen = computerID },
            page("settings-screens-unseen") { s in
                s.launchOnlyRemotes = launchOnlyRemotes
                s.config.keepScreensReady = true
                s.screensUnseenBy = s.launchOnlyRemotes.first
            },
            page("settings-screens-ready") { s in
                s.launchOnlyRemotes = launchOnlyRemotes
                s.config.keepScreensReady = true
            },
            page("settings-screens-legacy") { s in s.config = AppConfig() },
            page("settings-screens-trouble") { s in
                s.config = sampleConfig(count: ScreenConfig.limit)
                s.accessibilityTrusted = false
                s.legacyAppRunning = true
                s.configSaveFailed = true
                s.loginItemIssue = .needsApproval
                s.config.screenshot = true
            },
            page("settings-touch", tab: .touch) { _ in },
            page("settings-touch-dark", dark: true, tab: .touch) { s in s.config.screenshot = true },
            page("settings-general", tab: .general) { s in s.update.check = .upToDate },
            page("settings-general-dark", dark: true, tab: .general) { s in s.screenRecordingTrusted = true },
            page("settings-general-update-available", tab: .general) { s in s.update.check = .available(sampleFeed) },
            page("settings-general-too-old", tab: .general) { s in s.update.problem = .tooOld },
            RenderSample(name: "settings-add-screen") {
                AnyView(AddScreenSheet(state: sampleState(), intents: stub, close: {}))
            },
            RenderSample(name: "settings-add-screen-dark", dark: true) {
                AnyView(AddScreenSheet(state: sampleState(), intents: stub, close: {}))
            },
            RenderSample(name: "settings-screen-detail") {
                AnyView(ScreenDetailSheet(id: tabletID, state: sampleState(), intents: stub, navigation: stub, close: {}))
            },
            RenderSample(name: "settings-screen-detail-dark", dark: true) {
                AnyView(ScreenDetailSheet(id: .phone, state: sampleState(), intents: stub, navigation: stub, close: {}))
            },
            resolution("settings-resolution"),
            resolution("settings-resolution-sharpest-dark", dark: true, width: 1180),
            resolution("settings-resolution-phone", on: .phone, width: 800),
        ]
    }

    /// 调整分辨率的窗口：大小按 1280×800 的屏算（同 ResolutionWindowController）。width：配置里存的分辨率
    private static func resolution(_ name: String, on id: ScreenID = tabletID, dark: Bool = false, width: Int? = nil) -> RenderSample {
        let config = allScreens.first { $0.id == id }!
        let size = ResolutionWindowController.contentSize(for: config.resolution!, on: nil)
        return RenderSample(name: name, dark: dark, size: size) {
            let s = sampleState()
            if let i = s.config.screens.firstIndex(where: { $0.id == id }) { s.config.screens[i].baseWidth = width }
            return AnyView(ResolutionWindowView(id: id, state: s, intents: stub, close: {}).frame(width: size.width, height: size.height))
        }
    }

    private static func page(_ name: String, dark: Bool = false, tab: SettingsWindowController.Tab = .screens,
                             _ configure: @escaping @MainActor (AppState) -> Void) -> RenderSample {
        RenderSample(name: name, dark: dark) {
            let s = sampleState()
            configure(s)
            return switch tab {
            case .screens: AnyView(ScreensPage(state: s, intents: stub, navigation: stub))
            case .touch: AnyView(TouchPage(state: s, intents: stub))
            case .general: AnyView(GeneralPage(state: s, intents: stub, navigation: stub))
            }
        }
    }

    // MARK: 菜单栏

    private static var menu: [RenderSample] {
        [
            menuSample("menu-status-remote") { connected($0) },
            menuSample("menu-status-remote-dark", dark: true) { connected($0) },
            menuSample("menu-status-idle") { _ in },
            menuSample("menu-status-reconnecting") { s in
                s.connection = .reconnecting
                s.remoteName = Remotes.all.first?.identity.displayName
            },
            menuSample("menu-status-trouble") { s in s.accessibilityTrusted = false },
        ]
    }

    private static func menuSample(_ name: String, dark: Bool = false, configure: @escaping @MainActor (AppState) -> Void) -> RenderSample {
        RenderSample(name: name, dark: dark) {
            let s = sampleState()
            configure(s)
            return AnyView(MenuStatusView(text: StatusText(s), status: s.status).frame(width: MacTokens.Size.menuWidth).padding(.vertical, 6))
        }
    }

    // MARK: 关于与更新

    private static let sampleCurrent = Version(major: 2, minor: 1, patch: 0)

    /// 样例的 update.json：比当前新两版
    private static let sampleFeed: UpdateFeed = {
        let note = { (patch: Int, date: String, message: String) in
            ReleaseNote(version: Version(major: 2, minor: 1, patch: patch), date: date, tagMessage: message)
        }
        let package = UpdatePackage(file: "Snug-2.1.2.pack", chunks: [], files: [])
        return UpdateFeed(version: Version(major: 2, minor: 1, patch: 2), releases: [
            note(2, "2026-12-08", """
                Snug 2.1.2：窗口列表按最近使用排序

                改进
                - 窗口列表按最近使用排序，常用的窗口排在前面
                - 「正在打开」提示出现得更快

                修复
                - 个别 App 放上手机屏后字号没有放大
                """),
            note(1, "2026-11-28", """
                Snug 2.1.1：修复更新后偶尔显示未授权

                修复
                - 更新后个别情况下辅助功能显示为未授权，实际仍有效

                感谢社区用户反馈。
                """),
            note(0, "2026-11-20", "Snug 2.1.0：应用内更新"),
        ], package: package)
    }()

    private static var about: [RenderSample] {
        [
            RenderSample(name: "about") { AnyView(AboutView(remotes: Remotes.all.map(\.identity.displayName))) },
            RenderSample(name: "about-dark", dark: true) { AnyView(AboutView(remotes: Remotes.all.map(\.identity.displayName))) },
        ] + [
            ("about-update-downloading-dark", true, { (u: inout UpdateState) in
                u.check = .available(sampleFeed)
                u.phase = .downloading(0.42)
            }),
            ("about-update-unreachable", false, { (u: inout UpdateState) in u.problem = .unreachable(.tencent) }),
            ("about-update-cannot-replace", false, { (u: inout UpdateState) in
                u.check = .available(sampleFeed)
                u.problem = .cannotReplace
            }),
        ].map { name, dark, configure in
            RenderSample(name: name, dark: dark) {
                let s = sampleState()
                configure(&s.update)
                return AnyView(GeneralPage(state: s, intents: stub, navigation: stub))
            }
        }
    }

    private static var update: [RenderSample] {
        [
            updateSample("update") { _ in },
            updateSample("update-dark", dark: true) { _ in },
            updateSample("update-downloading") { $0.phase = .downloading(0.62) },
            updateSample("update-installing-dark", dark: true) { $0.phase = .installing },
            updateSample("update-corrupt") { $0.problem = .corrupt },
            updateSample("update-cannot-replace") { $0.problem = .cannotReplace },
            updateSample("update-one-behind", current: Version(major: 2, minor: 1, patch: 1)) { _ in },
        ]
    }

    private static func updateSample(_ name: String, dark: Bool = false, current: Version = sampleCurrent,
                                     _ configure: @escaping (inout UpdateState) -> Void) -> RenderSample {
        RenderSample(name: name, dark: dark) {
            let s = AppState()
            s.update.check = .available(sampleFeed)
            configure(&s.update)
            return AnyView(UpdateView(state: s, current: current, intents: stub, close: {}))
        }
    }

    // MARK: 欢迎页

    private static var welcome: [RenderSample] {
        [false, true].map { granted in
            RenderSample(name: granted ? "welcome-granted" : "welcome") {
                let s = AppState()
                s.accessibilityTrusted = granted
                s.remotes = Remotes.all.map(\.identity)
                return AnyView(WelcomeView(state: s, onDone: {}))
            }
        }
    }

    // MARK: 屏上的面板

    static let windows = [
        WindowInfo(key: WindowKey(pid: 1, id: 1), app: "Ghostty", bundleID: "com.mitchellh.ghostty", title: "~/projects/snug — zsh"),
        WindowInfo(key: WindowKey(pid: 2, id: 2), app: "Safari", bundleID: "com.apple.Safari", title: "Swift 文档 — Concurrency"),
        WindowInfo(key: WindowKey(pid: 3, id: 3), app: "备忘录", bundleID: "com.apple.Notes", title: "周末计划", minimized: true),
        WindowInfo(key: WindowKey(pid: 5, id: 5), app: "终端", bundleID: "com.apple.Terminal", title: "ssh build-server"),
        WindowInfo(key: WindowKey(pid: 1, id: 7), app: "Ghostty", bundleID: "com.mitchellh.ghostty", title: "~ — htop"),
    ]

    private static func app(_ bundleID: String, _ name: String) -> AppInfo { AppInfo(bundleID: bundleID, name: name, path: nil) }

    private static let installed: [InstalledApp] = [
        (app("com.apple.AppStore", "App Store"), "App Store"), (app("com.apple.calculator", "计算器"), "Calculator"),
        (app("com.apple.iCal", "日历"), "Calendar"), (app("com.apple.finder", "访达"), "Finder"),
        (app("com.mitchellh.ghostty", "Ghostty"), "Ghostty"), (app("com.apple.mail", "邮件"), "Mail"),
        (app("com.apple.Maps", "地图"), "Maps"), (app("com.apple.Music", "音乐"), "Music"),
        (app("com.apple.Notes", "备忘录"), "Notes"), (app("com.apple.Photos", "照片"), "Photos"),
        (app("com.apple.Preview", "预览"), "Preview"), (app("com.apple.reminders", "提醒事项"), "Reminders"),
        (app("com.apple.Safari", "Safari"), "Safari"), (app("com.apple.systempreferences", "系统设置"), "System Settings"),
        (app("com.apple.Terminal", "终端"), "Terminal"), (app("com.apple.TextEdit", "文本编辑"), "TextEdit"),
    ].map { InstalledApp($0.0, english: $0.1) }

    private static let running = [
        RunningApp(pid: 1, app: app("com.mitchellh.ghostty", "Ghostty"), windows: [windows[0], windows[4]]),
        RunningApp(pid: 2, app: app("com.apple.Safari", "Safari"), windows: [windows[1]]),
        RunningApp(pid: 3, app: app("com.apple.Notes", "备忘录"), windows: [windows[2]]),
        RunningApp(pid: 4, app: app("com.apple.finder", "访达"), windows: []),
        RunningApp(pid: 5, app: app("com.apple.Terminal", "终端"), windows: [windows[3]]),
    ]

    /// 样例机型库：几个品牌各几台（真的机型库在 Assets/device-models.json）
    private static let devices: DeviceCatalog = {
        let json = """
        {"phone": [
          {"name": "Apple", "models": [
            {"name": "iPhone 17 Pro Max", "year": 2025, "screen": [1320, 2868], "points": 440},
            {"name": "iPhone 17 Pro", "year": 2025, "screen": [1206, 2622], "points": 402},
            {"name": "iPhone 17", "year": 2025, "screen": [1206, 2622], "points": 402},
            {"name": "iPhone Air", "year": 2025, "screen": [1260, 2736], "points": 420}
          ]},
          {"name": "华为", "aliases": ["HUAWEI"], "models": [
            {"name": "Mate 70 Pro", "year": 2024, "screen": [1260, 2832]},
            {"name": "Pura 80 Ultra", "year": 2025, "screen": [1276, 2848]}
          ]},
          {"name": "小米", "aliases": ["Xiaomi"], "models": [
            {"name": "17 Pro Max", "year": 2025, "screen": [1200, 2608]},
            {"name": "15 Ultra", "year": 2025, "screen": [1440, 3200]}
          ]}
        ],
        "tablet": [
          {"name": "Apple", "models": [
            {"name": "iPad（第 10 代）", "year": 2022, "screen": [1640, 2360], "points": 820},
            {"name": "iPad Pro 11 英寸（M5）", "year": 2025, "screen": [1668, 2420], "points": 834}
          ]},
          {"name": "华为", "models": [{"name": "MatePad Pro 13.2 英寸", "year": 2025, "screen": [1920, 2880]}]}
        ],
        "computer": [
          {"name": "Apple", "models": [{"name": "MacBook Air 13 英寸（M4）", "year": 2025, "screen": [956, 1470], "notch": 33}]},
          {"name": "通用", "models": [{"name": "1920 × 1080", "year": 0, "screen": [1080, 1920]}]}
        ]}
        """
        return (try? DeviceCatalog(json: Data(json.utf8))) ?? .empty
    }()

    /// 每种屏：竖屏手机全套状态，横屏手机、平板横竖挑几种
    private static var screens: [RenderSample] {
        let placed = Desk.Placed(window: windows[0], zoom: 2)
        let portrait = [
            panel("phone-list") { _, _ in },
            panel("phone-placed") { s, _ in s.desks.desks[.phone]?.placed = placed },
            panel("phone-placed-dark", dark: true) { s, _ in s.desks.desks[.phone]?.placed = placed },
            panel("phone-opening") { s, _ in s.desks.desks[.phone]?.work = .opening(running[2].app) },
            panel("phone-placing") { s, _ in s.desks.desks[.phone]?.work = .placing(windows[1]) },
            panel("phone-quitting") { s, _ in s.desks.quitting = [2] },
            panel("phone-confirm-quit", confirming: .quit(2)) { _, _ in },
            panel("phone-confirm-close", confirming: .close(windows[4].key)) { s, _ in s.desks.desks[.phone]?.placed = placed },
            panel("phone-confirm-dismiss", confirming: .dismissScreen) { s, _ in s.desks.desks[.phone]?.placed = placed },
            panel("phone-confirm-dismiss-kept", confirming: .dismissScreen) { s, _ in
                s.desks.desks[.phone]?.placed = placed
                s.desks.desks[.phone]?.staysOnDismiss = true
            },
            panel("phone-kept-on-dismiss") { s, _ in s.desks.desks[.phone]?.notice = .keptOnDismiss },
            panel("phone-main") { s, _ in s.config.mainScreen = .phone },
            panel("phone-confirm-cancel-main", confirming: .cancelMain) { s, _ in s.config.mainScreen = .phone },
            panel("phone-dismissing-dark", dark: true) { s, _ in s.desks.desks[.phone]?.work = .dismissing },
            panel("phone-closing-dark", dark: true) { s, _ in
                s.desks.desks[.phone]?.placed = placed
                s.desks.closing = [windows[4].key]
            },
            panel("phone-notice") { s, _ in
                s.desks.desks[.phone]?.placed = placed
                s.desks.desks[.phone]?.notice = .windowUnresponsive(app: windows[1].app)
            },
            panel("phone-quit-stalled-dark", dark: true) { s, _ in s.desks.desks[.phone]?.notice = .quitStalled(app: "文本编辑", pid: 9) },
            panel("phone-all", tab: .all) { _, _ in },
            panel("phone-all-dark", dark: true, tab: .all) { s, _ in s.desks.desks[.phone]?.placed = placed },
            panel("phone-search") { _, pages in pages.open(.search) },
            panel("phone-search-results") { _, pages in
                pages.open(.search)
                pages.query = "s"
            },
            panel("phone-search-none-dark", dark: true) { _, pages in
                pages.open(.search)
                pages.query = "xyz"
            },
            panel("phone-model") { _, pages in pages.open(.model) },
            panel("phone-model-adjusted-dark", dark: true, width: 660) { _, pages in pages.open(.model) },
            panel("phone-resolution") { _, pages in pages.open(.resolution) },
            panel("phone-resolution-sharpest-dark", dark: true, width: 660) { _, pages in pages.open(.resolution) },
            panel("phone-resolution-wide", width: 900) { _, pages in pages.open(.resolution) },
            panel("phone-model-custom-dark", dark: true) { s, pages in
                s.config.screens[0].device = DeviceChoice(model: nil, screen: DeviceScreen(width: 1080, height: 2400))
                pages.open(.model)
            },
            panel("phone-model-search") { _, pages in
                pages.open(.model)
                pages.query = "17 pro"
            },
            panel("phone-model-none-dark", dark: true) { _, pages in
                pages.open(.model)
                pages.query = "nokia"
            },
            panel("phone-reshaping") { s, _ in
                s.config.screens[0].device = DeviceChoice(devices.models[4])
                s.desks.desks[.phone]?.work = .reshaping
            },
            panel("phone-reshaped") { s, _ in s.desks.desks[.phone]?.notice = .reshaped },
            panel("phone-empty", running: []) { _, _ in },
            panel("phone-loading", running: [], loaded: false) { _, _ in },
        ]
        let others = [
            panel("phone-landscape", on: landscapeID) { _, _ in },
            panel("phone-landscape-placed-dark", on: landscapeID, dark: true) { s, _ in s.desks.desks[landscapeID]?.placed = placed },
            panel("phone-landscape-all", on: landscapeID, tab: .all) { _, _ in },
            panel("phone-landscape-resolution", on: landscapeID, width: 1203) { _, pages in pages.open(.resolution) },
            panel("tablet-landscape", on: tabletID, tab: .all, selected: 3) { _, _ in },
            panel("tablet-landscape-placed", on: tabletID) { s, _ in s.desks.desks[tabletID]?.placed = placed },
            panel("tablet-landscape-dark", on: tabletID, dark: true) { _, _ in },
            panel("tablet-landscape-model", on: tabletID) { _, pages in pages.open(.model) },
            panel("tablet-landscape-resolution", on: tabletID) { _, pages in pages.open(.resolution) },
            panel("tablet-portrait", on: tabletPortraitID) { s, _ in s.desks.desks[tabletPortraitID]?.placed = placed },
        ]
        return portrait + others + screenshot
    }

    // MARK: 截图

    private static var screenshot: [RenderSample] {
        let fit = ScreenFit.standard
        let base = fit.size(width: fit.baseWidth)
        let wide = fit.size(width: fit.widths[min(3, fit.widths.count - 1)])
        let crop = { (size: CGSize) in
            AnyView(CropView(image: sampleShot, pixelSize: sampleShotSize, onCancel: {}, onDone: { _ in })
                .frame(width: size.width, height: size.height))
        }
        return [
            RenderSample(name: "phone-screenshot-thumbnail") {
                AnyView(ScreenshotThumbnail(image: sampleShot, scale: 1) {}.padding(12))
            },
            RenderSample(name: "phone-screenshot-notice-dark", dark: true) {
                AnyView(ScreenshotNoticeView(notice: .needsPermission, scale: 1).padding(12))
            },
            RenderSample(name: "phone-screenshot-crop", size: base) { crop(base) },
            RenderSample(name: "phone-screenshot-crop-wide", size: wide) { crop(wide) },
        ]
    }

    private static let sampleShotSize = CGSize(width: 1080, height: 1794)

    /// 一张假的窗口截图：标题栏 + 几行字的灰条
    private static let sampleShot = NSImage(size: sampleShotSize, flipped: true) { rect in
        NSColor.white.setFill()
        rect.fill()
        NSColor(white: 0.92, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: rect.width, height: 112).fill()
        for (i, color) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: 40 + CGFloat(i) * 56, y: 38, width: 36, height: 36)).fill()
        }
        NSColor(white: 0.8, alpha: 1).setFill()
        for row in 0..<14 {
            let width = rect.width - 160 - CGFloat(row % 3) * 180
            NSBezierPath(roundedRect: NSRect(x: 80, y: 200 + CGFloat(row) * 110, width: width, height: 36), xRadius: 18, yRadius: 18).fill()
        }
        return true
    }

    private static func panel(_ name: String, on id: ScreenID = .phone, dark: Bool = false, tab: TouchHomeView.Tab = .running,
                              confirming: TouchHomeView.Confirm? = nil, selected: Int32? = nil, running list: [RunningApp] = running,
                              loaded: Bool = true, width: Int? = nil, _ configure: @escaping @MainActor (AppState, TouchPages) -> Void) -> RenderSample {
        var config = allScreens.first { $0.id == id }!
        config.enabled = true
        // 调过分辨率的屏：面板按调过的基准宽度画
        config.baseWidth = width
        let fit = ScreenPlan.fit(of: config)
        let size = fit.size(width: fit.baseWidth)
        return RenderSample(name: name, dark: dark, size: size) {
            let s = sampleState()
            // 只有这一块屏（建好、在看），型号页、换档跟着它走
            s.config.screens = [config]
            connected(s)
            let pages = TouchPages()
            configure(s, pages)
            let catalog = AppCatalog(sample: list, installed: installed, loaded: loaded)
            return AnyView(TouchHomeView(screen: id, state: s, catalog: catalog, pages: pages, intents: stub, tab: tab,
                                         confirming: confirming, selected: selected)
                .frame(width: size.width, height: size.height)
                .screenPanel(id, state: s))
        }
    }

    // MARK: 电脑屏的 App 资源库

    /// 浮层的各状态，外加小竖条四态。电脑屏是 #22：htop 是挪过来的（能还原），Safari 在它的全屏空间里，
    /// 其余在内建屏、已最小化；访达开着但没窗口
    private static var library: [RenderSample] {
        let size = CGSize(width: MacTokens.Size.LibraryPanel.width, height: MacTokens.Size.LibraryPanel.maxHeight)
        let main = CGMainDisplayID()
        let spots: [WindowKey: WindowSpot] = [windows[0].key: .shown(main), windows[1].key: .fullScreen(22),
                                              windows[3].key: .shown(main), windows[4].key: .shown(22)]
        func sample(_ name: String, dark: Bool = false, page: ComputerLibraryModel.Page = .running, query: String = "",
                    loaded: Bool = true, _ configure: @escaping @MainActor (inout Desk.State) -> Void = { _ in }) -> RenderSample {
            RenderSample(name: name, dark: dark, size: size, inWindow: true) {
                let s = sampleState()
                s.config.screens[2].enabled = true
                connected(s)
                s.desks.desks[computerID]?.brought = [windows[4].key]
                if var desk = s.desks.desks[computerID] {
                    configure(&desk)
                    s.desks.desks[computerID] = desk
                }
                let model = ComputerLibraryModel()
                model.page = page
                model.query = query
                let catalog = AppCatalog(sample: running, installed: installed, spots: spots, loaded: loaded)
                let actions = ComputerLibraryActions(focus: { _ in }, pull: { _ in }, putBack: { _ in }, open: { _ in }, dismiss: {})
                return AnyView(ComputerLibraryView(id: computerID, state: s, catalog: catalog, model: model, actions: actions))
            }
        }
        let panels = [false, true].flatMap { dark in
            [sample("library-running\(dark ? "-dark" : "")", dark: dark), sample("library-all\(dark ? "-dark" : "")", dark: dark, page: .all)]
        } + [
            sample("library-search", query: "yu"),
            sample("library-search-empty", query: "xyz"),
            sample("library-working") { $0.work = .placing(windows[1]) },
            sample("library-notice") { $0.notice = .windowGone(app: "Safari") },
            sample("library-loading", loaded: false),
        ]
        let tabs = RenderSample(name: "library-tab") {
            AnyView(HStack(spacing: MacTokens.Space.xl) {
                tab(open: false) { _ in }
                tab(open: true) { _ in }
                tab(open: false) { $0.work = .opening(running[1].app) }
                tab(open: false) { $0.notice = .windowGone(app: "Safari") }
            }
            .padding(MacTokens.Space.xl))
        }
        return panels + [tabs]
    }

    private static func tab(open: Bool, _ configure: @MainActor (inout Desk.State) -> Void) -> some View {
        let s = sampleState()
        s.config.screens[2].enabled = true
        connected(s)
        if var desk = s.desks.desks[computerID] {
            configure(&desk)
            s.desks.desks[computerID] = desk
        }
        let model = ComputerLibraryModel()
        model.open = open
        return ComputerTabView(id: computerID, state: s, model: model, toggle: {})
    }
}
