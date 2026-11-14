// 设置窗口：一页。顶部是此刻的状态，下面是总开关和两项微调，再下面是开机启动和权限。
// 每行配 SF Symbols 图标，说明只用短词。只读 AppState，意图走 AppIntents
import AppKit
import SwiftUI
import SnugCore

struct SettingsView: View {
    let state: AppState
    let intents: any AppIntents
    let navigation: any Navigation

    var body: some View {
        Form {
            Section { StatusHeader(state: state, intents: intents) }
            Section {
                Toggle(isOn: binding(state.config.phoneScreen, intents.setPhoneScreen)) {
                    SettingLabel("手机屏", detail: "UU远程 中增加竖屏", symbol: "iphone", tint: .blue)
                }
                Toggle(isOn: binding(state.config.gestures, intents.setGestures)) {
                    SettingLabel("触控手势", detail: "单指滚动 · 长按选择 · 长按松开右键", symbol: "hand.draw.fill", tint: .orange)
                }
                .disabled(!state.config.phoneScreen)
                LabeledContent {
                    HStack(spacing: 8) {
                        Text(state.config.zoomSteps == 0 ? "不放大" : "+\(state.config.zoomSteps) 级")
                            .monospacedDigit()
                            .fixedSize()
                        Stepper("字号放大", value: binding(state.config.zoomSteps, intents.setZoomSteps), in: AppConfig.zoomStepsRange)
                            .labelsHidden()
                    }
                } label: {
                    SettingLabel("字号放大", detail: "终端、编辑器", symbol: "textformat.size", tint: .green)
                }
                .disabled(!state.config.phoneScreen)
            }
            Section {
                Toggle(isOn: binding(state.launchAtLogin, intents.setLaunchAtLogin)) {
                    SettingLabel("开机启动", symbol: "power", tint: .gray)
                }
                LabeledContent {
                    if state.accessibilityTrusted {
                        Label("已授权", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("授权…") { navigation.openWelcome() }
                    }
                } label: {
                    SettingLabel(PermissionName.accessibility, detail: "用于移动窗口与转换手势", symbol: "hand.raised.fill", tint: .indigo)
                }
            }
            Section {
                HStack {
                    Button { navigation.openAbout() } label: {
                        HStack(spacing: 8) {
                            Label("关于 Snug", systemImage: "info.circle")
                            // 有新版本：标在「关于 Snug」上，更新在那里面
                            if state.update.hasNewVersion {
                                Text(["新版本", state.update.available?.version.description].compactMap { $0 }.joined(separator: " "))
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(.blue, in: Capsule())
                            }
                        }
                    }
                    Spacer()
                    Button("退出 Snug", systemImage: "power") { intents.quit() }
                        .help("还原窗口后退出")
                }
                .buttonStyle(.link)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func binding<T>(_ value: T, _ set: @escaping @MainActor (T) -> Void) -> Binding<T> {
        Binding(get: { value }, set: { set($0) })
    }
}

/// 顶部：此刻的状态，以及需要用户处理的提示
private struct StatusHeader: View {
    let state: AppState
    let intents: any AppIntents

    var body: some View {
        let text = StatusText(state)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(tint)
                    .frame(width: 40, height: 40)
                    .background(tint.opacity(0.15), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(text.headline).font(.headline)
                    if let detail = text.detail { Text(detail).foregroundStyle(.secondary) }
                }
            }
            if state.legacyAppRunning {
                HStack {
                    Label("旧版「UU远程伴侣」运行中", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("退出旧版") { intents.quitLegacyApp() }
                }
            }
            if state.configSaveFailed {
                Label("设置未保存", systemImage: "exclamationmark.circle.fill").foregroundStyle(.orange)
            }
            if let issue = state.loginItemIssue {
                Label(issue.text, systemImage: "exclamationmark.circle.fill").foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
    }

    private var symbol: String {
        if !state.accessibilityTrusted { return "hand.raised.fill" }
        switch state.connection {
        case .idle: return "iphone.gen3"
        case .reconnecting: return "arrow.triangle.2.circlepath"
        case .connected: return "iphone.gen3.radiowaves.left.and.right"
        }
    }

    private var tint: Color {
        if !state.accessibilityTrusted { return .orange }
        return state.connection == .connected ? .green : .accentColor
    }
}

@MainActor
final class SettingsWindowController {
    private let state: AppState
    private let intents: any AppIntents
    private weak var navigation: (any Navigation)?
    private var window: NSWindow?

    init(state: AppState, intents: any AppIntents, navigation: any Navigation) {
        self.state = state
        self.intents = intents
        self.navigation = navigation
    }

    func show() {
        if window == nil, let navigation {
            window = NSWindow(hosting: SettingsView(state: state, intents: intents, navigation: navigation),
                              title: "Snug 设置", style: [.titled, .closable, .miniaturizable])
        }
        window?.present(activating: true)
    }
}
