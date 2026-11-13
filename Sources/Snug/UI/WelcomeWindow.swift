// 欢迎页：第一次打开时出现，三步讲清 Snug 怎么用，再请用户授予辅助功能权限（PermissionFlow 打开系统设置，
// 旁边浮出一个小窗口，把 Snug 拖进列表即可）。之后缺权限时从设置里也能再打开。
// 授权状态读 AppState（AppController 每拍刷新），这里不自己轮询
import AppKit
import PermissionFlow
import SwiftUI
import SnugCore

struct WelcomeView: View {
    let state: AppState
    let onDone: () -> Void

    private var appURL: URL { Bundle.main.bundleURL }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("欢迎使用 Snug").font(.largeTitle.bold())
                Text("手机远程 Mac 的显示与触控增强").foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 16) {
                Step(symbol: "iphone.gen3", title: "选择「\(PhoneScreenSpec.name)」", detail: "UU远程 屏幕列表中切换；不切换则一切如常")
                Step(symbol: "hand.tap.fill", title: "点选窗口", detail: "铺满手机屏，字号自动放大")
                Step(symbol: "hand.draw.fill", title: "触控手势", detail: "单指滚动 · 长按选择 · 长按松开右键")
            }
            permission
            HStack {
                Spacer()
                Button(state.accessibilityTrusted ? "完成" : "稍后", action: onDone)
                    .keyboardShortcut(state.accessibilityTrusted ? .defaultAction : nil)
                    .controlSize(.large)
            }
        }
        .padding(32)
        .frame(width: 520)
    }

    private var permission: some View {
        let granted = state.accessibilityTrusted
        // macOS 27 起叫「设备控制和数据访问」，更早叫「辅助功能」；固定取简体中文
        let name = PermissionFlowResources.localizedString(for: PermissionFlowResources.accessibilityName(), localeIdentifier: "zh-Hans")
        return HStack(spacing: 16) {
            Image(systemName: "hand.raised.fill")
                .font(.title2)
                .foregroundStyle(granted ? .green : .orange)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(.headline)
                Text(granted ? "已授权" : "用于移动窗口与转换手势").foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            if granted {
                Image(systemName: "checkmark.circle.fill").font(.title).foregroundStyle(.green)
            } else {
                PermissionFlowButton(
                    pane: .accessibility,
                    suggestedAppURLs: [appURL],
                    configuration: .init(requiredAppURLs: [appURL], promptForAccessibilityTrust: false, localeIdentifier: "zh-Hans")
                ) { _ in
                    Text("授权")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct Step: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

@MainActor
final class WelcomeWindowController {
    private let state: AppState
    private var window: NSWindow?
    private var onDone: (() -> Void)?
    private var closeObserver: (any NSObjectProtocol)?

    init(state: AppState) { self.state = state }

    func show(onDone: (() -> Void)? = nil) {
        if let onDone { self.onDone = onDone }
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: WelcomeView(state: state) { [weak self] in
                self?.window?.close()
            }))
            w.styleMask = [.titled, .closable]
            w.title = "Snug"
            w.isReleasedWhenClosed = false
            w.center()
            closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w,
                                                                   queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.finish() }
            }
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private func finish() {
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        closeObserver = nil
        window = nil
        let done = onDone
        onDone = nil
        done?()
    }
}
