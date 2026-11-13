// 「找回屏幕」页：只保留虚拟屏时，万一远程结束后屏幕没亮，用这里的办法找回
import SwiftUI
import SystemSettingsKit
import SnugCore

struct RecoveryPage: View {
    let state: AppState
    let intents: any AppIntents

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("远程结束时被熄灭的屏幕会自动点亮。万一没亮，用下面的办法找回。")
                .foregroundStyle(.secondary)
            Card {
                Text("快捷键").font(.headline)
                Text("在这台 Mac 前同时按下这四个键，所有屏幕立刻点亮，远程不受影响。")
                    .font(.callout).foregroundStyle(.secondary)
                HotkeyKeysView()
                Text("不在 Mac 前时：再远程进来，点下面的「立即恢复屏幕」，效果一样。")
                    .font(.callout).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Button("立即恢复屏幕") { intents.restoreScreensNow() }
                        .disabled(!state.display.physicalOff)
                        .help(state.display.physicalOff ? "也可以按 ⌃⌥⌘9" : "现在没有熄灭的屏幕")
                    Button("还原屏幕布局") { intents.restoreLayoutNow() }
                        .disabled(!state.display.layoutPending)
                        .help(state.display.layoutPending ? "按远程前记下的位置和分辨率还原" : "没有待还原的布局")
                }
            }
            Card {
                SettingToggle(title: "看门狗", tag: "可选",
                              detail: "在后台每 5 秒看一眼。Snug 崩溃、卡住超过 10 秒，或已经不用熄屏而屏幕还黑着时，自动点亮。",
                              isOn: state.config.watchdogEnabled, set: intents.setWatchdogEnabled)
                if state.config.watchdogEnabled {
                    HStack(spacing: 12) {
                        Label(state.watchdogRunning ? "正在值守" : "没有运行",
                              systemImage: state.watchdogRunning ? "checkmark.circle.fill" : "exclamationmark.circle")
                            .foregroundStyle(state.watchdogRunning ? .green : .orange)
                        if !state.watchdogRunning {
                            Button("去系统设置里允许") { SystemSettings.open(.loginItems) }
                        }
                    }
                }
                Text("打开时 macOS 会提示「SnugWatchdog」已添加后台项目。关掉这里就彻底移除。")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
