// 「远程」页：Snug 的总开关、开机启动、辅助功能权限
import SwiftUI
import SnugCore

struct SessionPage: View {
    let state: AppState
    let intents: any AppIntents
    let navigation: any Navigation

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Snug 一直留意 UU远程 的连接：连上时按你的设置调整这台 Mac，断开后原样还原。")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Card {
                SettingToggle(title: "暂停 Snug", detail: "暂停后照常检测连接，但不做任何调整。",
                              isOn: state.config.paused, set: intents.setPaused)
                Divider()
                SettingToggle(title: "开机启动", detail: "登录后在菜单栏待命，占用内存约 60 MB。",
                              isOn: state.launchAtLogin, set: intents.setLaunchAtLogin)
            }
            Card {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("辅助功能权限").font(.headline)
                        Text("用来认出是哪台设备在远程，并读取 UU远程 里的设备列表。不读其他内容。")
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    if state.accessibilityTrusted {
                        Label("已授权", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("去授权…") { navigation.openPermissions() }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }
}
