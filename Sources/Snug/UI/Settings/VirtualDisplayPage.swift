// 「虚拟屏」页：可选功能，默认关。开关、它的代价（macOS 会重排窗口）、只保留虚拟屏、各控制端的分辨率
import SwiftUI
import SnugCore

struct VirtualDisplayPage: View {
    let state: AppState
    let drafts: DeviceDrafts
    let intents: any AppIntents
    var forRender = false

    var body: some View {
        let config = state.config
        VStack(alignment: .leading, spacing: 16) {
            Card {
                SettingToggle(title: "远程时准备虚拟屏", tag: "可选，默认关闭",
                              detail: "按控制端屏幕的分辨率新建一块虚拟屏并设为主屏，手机上画面铺满、文字清晰。",
                              isOn: config.virtualDisplayEnabled, set: intents.setVirtualDisplayEnabled)
                Callout(symbol: "exclamationmark.triangle",
                        text: "新建和移除虚拟屏时，macOS 会重新排列窗口和桌面图标。远程结束后 Snug 会还原各屏幕的位置和分辨率，但窗口不一定回到原处。",
                        tint: .orange)
                Divider()
                SettingToggle(title: "远程时只保留虚拟屏",
                              detail: "熄灭这台 Mac 的其他屏幕，窗口和程序坞不会跑到看不见的屏幕上。远程结束自动点亮；万一没亮，看「找回屏幕」。",
                              isOn: config.keepOnlyVirtual, enabled: config.virtualDisplayEnabled && state.physicalControlAvailable,
                              set: intents.setKeepOnlyVirtual)
                if !state.physicalControlAvailable {
                    Callout(symbol: "info.circle", text: "这台 Mac 上熄灭屏幕用的系统接口不可用，这一项无法打开。")
                }
            }
            if !config.virtualDisplayEnabled {
                Callout(symbol: "info.circle", text: "虚拟屏关着。下面填的分辨率，打开上面的开关后才会用到。")
            }
            DeviceTable(state: state, drafts: drafts, intents: intents, forRender: forRender)
        }
    }
}
