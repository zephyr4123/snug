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
    /// 提示挂着、还没定下来时才有；定下来（点了按钮，或旧版自己退了）只走一次
    private var decide: (@MainActor (Bool) -> Void)?

    func show(quitLegacy: @escaping @MainActor () -> Void, proceed: @escaping @MainActor () -> Void) {
        guard window == nil else { return }
        decide = { [weak self] quit in
            guard let self, decide != nil else { return }
            decide = nil
            window?.close()
            window = nil
            guard quit else { return proceed() }
            quitLegacy()
            // 旧版退出前要先还原它改过的屏幕（最多约 8 秒），等它真走了再开始监控，免得两边同时改屏幕
            LegacyApp.waitUntilGone(timeout: 12, then: proceed)
        }
        let view = LegacyNoticeView(quitLegacy: { [weak self] in self?.decide?(true) },
                                    keepBoth: { [weak self] in self?.decide?(false) })
        let w = NSWindow(contentViewController: NSHostingController(rootView: view))
        w.title = "Snug"
        w.styleMask = [.titled]
        w.isReleasedWhenClosed = false
        w.center()
        window = w
        NSApp.activate()
        w.makeKeyAndOrderFront(nil)
    }

    /// 旧版已经退出（从菜单、设置或旧版自己的菜单退的）：提示还挂着就收起，照常开始监控。
    /// 不然提示被别的窗口盖住时，监控一直不开始，菜单上却显示「等待连接」
    func legacyGone() {
        decide?(false)
    }
}
