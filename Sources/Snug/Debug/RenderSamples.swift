// --render-* 用的样例状态。窗口标题和设备名都是通用的，不带任何个人信息
import SwiftUI
import SnugCore

@MainActor
struct RenderSample {
    let name: String
    var dark = false
    /// nil：按内容自适应
    var size: CGSize?
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
        case .phone: phone
        case .update: update
        }
    }

    // MARK: 设置

    private static var settings: [RenderSample] {
        [
            setting("settings-idle") { _ in },
            setting("settings-ready") { s in
                connected(s)
            },
            setting("settings-in-use-dark", dark: true) { s in
                connected(s)
                s.streamedDisplay = 14
                s.phone.placed = PhoneDesk.Placed(window: windows[0], zoom: 2)
            },
            setting("settings-update-available") { s in s.update.check = .available(sampleFeed) },
            setting("settings-trouble") { s in
                s.accessibilityTrusted = false
                s.legacyAppRunning = true
                s.configSaveFailed = true
                s.loginItemIssue = .needsApproval
            },
        ]
    }

    private static func setting(_ name: String, dark: Bool = false, _ configure: @escaping @MainActor (AppState) -> Void) -> RenderSample {
        RenderSample(name: name, dark: dark) {
            let s = AppState()
            s.accessibilityTrusted = true
            s.launchAtLogin = true
            configure(s)
            return AnyView(SettingsView(state: s, intents: stub, navigation: stub))
        }
    }

    private static func connected(_ s: AppState) {
        s.connection = .connected
        s.controller = "iPhone 17 Pro Max"
        s.phone.screen = .ready(14)
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
            aboutSample("about") { $0.check = .upToDate },
            aboutSample("about-dark", dark: true) { $0.check = .upToDate },
            aboutSample("about-available") { $0.check = .available(sampleFeed) },
            aboutSample("about-downloading-dark", dark: true) { u in
                u.check = .available(sampleFeed)
                u.phase = .downloading(0.42)
            },
            aboutSample("about-unreachable") { $0.problem = .unreachable(.tencent) },
            aboutSample("about-cannot-replace") { u in
                u.check = .available(sampleFeed)
                u.problem = .cannotReplace
            },
        ]
    }

    private static func aboutSample(_ name: String, dark: Bool = false, _ configure: @escaping (inout UpdateState) -> Void) -> RenderSample {
        RenderSample(name: name, dark: dark) {
            let s = AppState()
            configure(&s.update)
            return AnyView(AboutView(state: s, intents: stub, navigation: stub))
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
        ]
    }

    private static func updateSample(_ name: String, dark: Bool = false, _ configure: @escaping (inout UpdateState) -> Void) -> RenderSample {
        RenderSample(name: name, dark: dark) {
            let s = AppState()
            s.update.check = .available(sampleFeed)
            configure(&s.update)
            return AnyView(UpdateView(state: s, current: sampleCurrent, intents: stub, close: {}))
        }
    }

    // MARK: 欢迎页

    private static var welcome: [RenderSample] {
        [false, true].map { granted in
            RenderSample(name: granted ? "welcome-granted" : "welcome") {
                let s = AppState()
                s.accessibilityTrusted = granted
                return AnyView(WelcomeView(state: s, onDone: {}))
            }
        }
    }

    // MARK: 手机屏

    static let windows = [
        WindowInfo(key: WindowKey(pid: 1, id: 1), app: "Ghostty", bundleID: "com.mitchellh.ghostty", title: "~/projects/snug — zsh"),
        WindowInfo(key: WindowKey(pid: 2, id: 2), app: "Safari", bundleID: "com.apple.Safari", title: "Swift 文档 — Concurrency"),
        WindowInfo(key: WindowKey(pid: 3, id: 3), app: "备忘录", bundleID: "com.apple.Notes", title: "周末计划"),
        WindowInfo(key: WindowKey(pid: 4, id: 4), app: "访达", bundleID: "com.apple.finder", title: "下载"),
        WindowInfo(key: WindowKey(pid: 5, id: 5), app: "终端", bundleID: "com.apple.Terminal", title: "ssh build-server"),
        WindowInfo(key: WindowKey(pid: 6, id: 6), app: "日历", bundleID: "com.apple.iCal", title: "11月"),
    ]

    private static var phone: [RenderSample] {
        [
            phoneSample("phone-list") { _ in },
            phoneSample("phone-placed") { s in s.phone.placed = PhoneDesk.Placed(window: windows[0], zoom: 2) },
            phoneSample("phone-placed-dark", dark: true) { s in s.phone.placed = PhoneDesk.Placed(window: windows[0], zoom: 2) },
            phoneSample("phone-placing") { s in s.phone.work = .placing(windows[1]) },
            phoneSample("phone-notice") { s in
                s.phone.placed = PhoneDesk.Placed(window: windows[3], zoom: 0)
                s.phone.notice = .windowUnresponsive(app: windows[3].app)
            },
            phoneSample("phone-notice-dark", dark: true) { s in s.phone.notice = .windowGone(app: windows[2].app) },
            phoneSample("phone-empty", windows: []) { _ in },
            phoneSample("phone-loading", windows: [], loaded: false) { _ in },
        ]
    }

    private static func phoneSample(_ name: String, dark: Bool = false, windows list: [WindowInfo] = windows, loaded: Bool = true,
                                    _ configure: @escaping @MainActor (AppState) -> Void) -> RenderSample {
        let size = CGSize(width: PhoneScreenSpec.width, height: PhoneScreenSpec.height)
        return RenderSample(name: name, dark: dark, size: size) {
            let s = AppState()
            s.phone.screen = .ready(14)
            configure(s)
            return AnyView(PhoneHomeView(state: s, catalog: WindowCatalog(sample: list, loaded: loaded), intents: stub)
                .frame(width: size.width, height: size.height))
        }
    }
}
