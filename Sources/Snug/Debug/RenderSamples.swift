// --render-settings / --render-permissions 用的样例状态。设备名用通用型号，不带任何个人信息
import SwiftUI
import SnugCore

@MainActor
struct RenderSample {
    let name: String
    var dark = false
    let view: () -> AnyView
}

@MainActor
enum RenderSamples {
    private static let stub = RenderStub()

    static let devices = [
        DeviceProfile(name: "iPhone 17 Pro Max", kind: .phone, width: 2868, height: 1320, uuComputer: false, platform: "ios"),
        DeviceProfile(name: "iPad Air", kind: .tablet, width: 0, height: 0, uuComputer: false, platform: "ios"),
        DeviceProfile(name: "OPPO Pad 3", kind: .tablet, width: 2800, height: 2000, uuComputer: false, platform: "android"),
        DeviceProfile(name: "MacBook Air", kind: .computer, width: 0, height: 0, uuComputer: true, platform: "macos"),
        DeviceProfile(name: "办公室台式机", kind: .computer, width: 0, height: 0, uuComputer: true, platform: "windows"),
    ]

    static var settings: [RenderSample] {
        [
            sample("settings-session-idle", page: .session) { s in
                s.accessibilityTrusted = true
                s.launchAtLogin = true
            },
            sample("settings-session-connected", page: .session) { s in
                connected(s)
                s.legacyAppRunning = true
            },
            sample("settings-session-trouble", page: .session) { s in
                s.connection = .reconnecting
                s.config.virtualDisplayEnabled = true
                s.display.physicalOff = true
                s.display.breakerTripped = true
                s.display.issue = "恢复物理屏 [5] 失败（CGError=1001），后台继续重试"
                s.notice = "设置没能保存：磁盘已满"
            },
            sample("settings-session-paused-dark", page: .session, dark: true) { s in
                s.config.paused = true
                s.accessibilityTrusted = true
            },
            sample("settings-virtual-off", page: .virtualDisplay, invalidDraft: true) { s in
                s.accessibilityTrusted = true
            },
            sample("settings-virtual-on", page: .virtualDisplay) { s in
                connected(s)
                s.config.keepOnlyVirtual = true
                s.deviceImport = .finished("已从 UU远程 导入 5 台设备（不含这台 Mac）。")
            },
            sample("settings-virtual-on-dark", page: .virtualDisplay, dark: true, invalidDraft: true) { s in
                s.config.virtualDisplayEnabled = true
                s.deviceImport = .failed("没读到设备列表。打开 UU远程 的「全部设备」页，再点「从 UU远程 导入」。")
            },
            sample("settings-virtual-empty", page: .virtualDisplay) { s in
                s.config.devices = []
                s.physicalControlAvailable = false
            },
            sample("settings-recovery", page: .recovery) { s in
                connected(s)
                s.config.watchdogEnabled = true
                s.display.layoutPending = true
            },
            sample("settings-recovery-dark", page: .recovery, dark: true) { s in
                s.config.watchdogEnabled = true
                s.watchdogRunning = true
            },
        ]
    }

    static var permissions: [RenderSample] {
        [false, true].map { granted in
            RenderSample(name: granted ? "permissions-granted" : "permissions-pending") {
                let s = AppState()
                s.accessibilityTrusted = granted
                return AnyView(PermissionsView(state: s, onDone: {}))
            }
        }
    }

    /// 正在远程、虚拟屏已就位、其余屏幕熄灭
    private static func connected(_ s: AppState) {
        s.connection = .connected
        s.controller = "iPhone 17 Pro Max"
        s.streamedDisplay = StreamedDisplay(id: 14, name: "Snug · iPhone 17 Pro Max")
        s.config.virtualDisplayEnabled = true
        s.display.activeProfile = devices[0]
        s.display.physicalOff = true
    }

    private static func sample(_ name: String, page: SettingsPage, dark: Bool = false, invalidDraft: Bool = false,
                               _ configure: @escaping @MainActor (AppState) -> Void) -> RenderSample {
        RenderSample(name: name, dark: dark) {
            let s = AppState()
            s.config.devices = devices
            configure(s)
            let ui = SettingsUIModel(page: page)
            if invalidDraft {
                // 「OPPO Pad 3」只改了宽、高被清空：这一行就地报错，其余行照常
                var row = devices[2]
                row.height = 0
                ui.drafts.edit(row, saved: devices[2], typing: true, intents: stub)
            }
            return AnyView(SettingsView(state: s, ui: ui, intents: stub, navigation: stub, forRender: true))
        }
    }
}
