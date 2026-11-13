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
        case .about: [false, true].map { dark in RenderSample(name: dark ? "about-dark" : "about", dark: dark) { AnyView(AboutView()) } }
        case .legacy: [RenderSample(name: "legacy") { AnyView(LegacyNoticeView(quitLegacy: {}, keepBoth: {})) }]
        case .phone: phone
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
            setting("settings-trouble") { s in
                s.accessibilityTrusted = false
                s.legacyAppRunning = true
                s.configSaveFailed = true
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
            phoneSample("phone-notice") { s in
                s.phone.placed = PhoneDesk.Placed(window: windows[3], zoom: 0)
                s.phone.notice = .windowGone
            },
            phoneSample("phone-empty", windows: []) { _ in },
        ]
    }

    private static func phoneSample(_ name: String, dark: Bool = false, windows list: [WindowInfo] = windows,
                                    _ configure: @escaping @MainActor (AppState) -> Void) -> RenderSample {
        let size = CGSize(width: PhoneScreenSpec.width, height: PhoneScreenSpec.height)
        return RenderSample(name: name, dark: dark, size: size) {
            let s = AppState()
            s.phone.screen = .ready(14)
            configure(s)
            return AnyView(PhoneHomeView(state: s, catalog: WindowCatalog(sample: list), intents: stub)
                .frame(width: size.width, height: size.height))
        }
    }
}
