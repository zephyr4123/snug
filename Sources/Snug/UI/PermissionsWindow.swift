// 权限窗口：用 PermissionFlow 引导授权（打开系统设置的隐私页 + 拖拽授权的小窗口）。
// 授权状态读 AppState（AppController 每秒刷新一次），这里不自己轮询
import AppKit
import PermissionFlow
import SwiftUI
import SnugCore

struct PermissionsView: View {
    let state: AppState
    let onDone: () -> Void

    private var appURL: URL { Bundle.main.bundleURL }

    var body: some View {
        let granted = state.accessibilityTrusted
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("允许 Snug 读取 UU远程 里的设备名称").font(.title2.bold())
                Text("远程开始时才能认出是哪台设备，按它的分辨率准备虚拟屏。").foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "hand.raised.fill").font(.title2).foregroundStyle(.tint).frame(width: 32)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        // macOS 27 起叫「设备控制和数据访问」，更早叫「辅助功能」；固定取简体中文
                        Text(PermissionFlowResources.localizedString(
                            for: PermissionFlowResources.accessibilityName(), localeIdentifier: "zh-Hans")).font(.headline)
                        Text("必需").font(.caption).foregroundStyle(.secondary)
                    }
                    Text("只读 UU远程 窗口里显示的设备名称，不读其他内容。").foregroundStyle(.secondary)
                    if !granted {
                        Text("点「授权」会打开系统设置，旁边出现一个小窗口，把里面的 Snug 拖进列表就好。\n如果列表里已经有 Snug、开关也开着，却还显示未授权：选中它，点「−」删掉，再拖一次。")
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 8) {
                    Label(granted ? "已授权" : "未授权", systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .foregroundStyle(granted ? .green : .orange)
                    if !granted {
                        PermissionFlowButton(
                            pane: .accessibility,
                            suggestedAppURLs: [appURL],
                            configuration: .init(requiredAppURLs: [appURL], promptForAccessibilityTrust: false, localeIdentifier: "zh-Hans")
                        ) { _ in
                            // 状态由左边的标签统一显示，按钮只负责发起授权
                            Label("授权", systemImage: "arrow.right.circle")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
            HStack {
                if granted { Label("准备好了", systemImage: "checkmark.seal.fill").foregroundStyle(.green) }
                Spacer()
                Button(granted ? "完成" : "稍后再说", action: onDone).keyboardShortcut(granted ? .defaultAction : nil)
            }
        }
        .padding(20)
        .frame(width: 620)
    }
}

@MainActor
final class PermissionsWindowController {
    private let state: AppState
    private var window: NSWindow?
    private var onDone: (() -> Void)?
    private var closeObserver: (any NSObjectProtocol)?

    init(state: AppState) { self.state = state }

    /// autoClose：授权完成后自动关闭（首次启动引导时用）
    func show(autoClose: Bool, onDone: (() -> Void)?) {
        if let onDone { self.onDone = onDone }
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingView(rootView: PermissionsView(state: state) { [weak self] in self?.window?.close() })
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "权限设置"
        w.contentView = hosting
        w.isReleasedWhenClosed = false
        w.center()
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w,
                                                               queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish() }
        }
        window = w
        if autoClose, !state.accessibilityTrusted { closeWhenGranted() }
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 授权状态由未授权变成已授权时，稍等一下让用户看到「已授权」再关
    private func closeWhenGranted() {
        withObservationTracking {
            _ = state.accessibilityTrusted
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.window != nil else { return }
                    guard self.state.accessibilityTrusted else { return self.closeWhenGranted() }
                    Log.info("辅助功能已授权")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        MainActor.assumeIsolated { self.window?.close() }
                    }
                }
            }
        }
    }

    private func finish() {
        window = nil
        let done = onDone
        onDone = nil
        done?()
    }
}
