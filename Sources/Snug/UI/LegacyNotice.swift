// 旧版共存提示：启动时发现旧版「UU远程伴侣」在运行。它远程时会建虚拟屏、关物理屏，和 Snug 一起跑会互相干扰。
// 问清楚再开始监控：退出旧版，或者都留着（之后设置窗口和菜单里还能一键退出旧版）
import AppKit
import SwiftUI

struct LegacyNoticeView: View {
    let quitLegacy: () -> Void
    let keepBoth: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill").font(.title).foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 8) {
                    Text("旧版「UU远程伴侣」运行中").font(.title3.bold())
                    Text("与 Snug 同时运行将相互干扰")
                        .fixedSize(horizontal: false, vertical: true)
                    Text("退出后自动还原 · 可从「应用程序」移除")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack {
                Spacer()
                Button("保留两者", action: keepBoth)
                Button("退出旧版", action: quitLegacy).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
    }
}

@MainActor
final class LegacyNoticeWindowController {
    private var window: NSWindow?

    func show(quitLegacy: @escaping @MainActor () -> Void, proceed: @escaping @MainActor () -> Void) {
        guard window == nil else { return }
        var decided = false
        let decide: @MainActor (Bool) -> Void = { [weak self] quit in
            guard !decided else { return }
            decided = true
            self?.window?.close()
            self?.window = nil
            guard quit else { return proceed() }
            quitLegacy()
            // 旧版退出前要先还原它改过的屏幕（最多约 8 秒），等它真走了再开始监控，免得两边同时改屏幕
            LegacyApp.waitUntilGone(timeout: 12, then: proceed)
        }
        let view = LegacyNoticeView(quitLegacy: { decide(true) }, keepBoth: { decide(false) })
        let w = NSWindow(contentViewController: NSHostingController(rootView: view))
        w.title = "Snug"
        w.styleMask = [.titled]
        w.isReleasedWhenClosed = false
        w.center()
        window = w
        NSApp.activate()
        w.makeKeyAndOrderFront(nil)
    }
}
