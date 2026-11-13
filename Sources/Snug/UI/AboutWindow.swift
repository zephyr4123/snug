// 「关于」窗口：名称、版本、来源、致谢与免责声明
import AppKit
import SwiftUI

struct AboutView: View {
    private struct Credit: Identifiable {
        let name, url, author, usage: String
        var id: String { name }
    }

    private let credits = [
        Credit(name: "UUyc-companion", url: "https://github.com/aoyamashou/UUyc-companion",
               author: "AoyamaShou", usage: "项目前身"),
        Credit(name: "PermissionFlow", url: "https://github.com/jaywcjlove/PermissionFlow",
               author: "小弟调调（jaywcjlove）", usage: "授权引导"),
        Credit(name: "Better Remote", url: "https://github.com/pincc-debug/better-remote",
               author: "pincc-debug", usage: "单指滚动思路"),
        Credit(name: "FreeDisplay", url: "https://github.com/huberdf/FreeDisplay",
               author: "huberdf", usage: "虚拟屏接口声明"),
    ]

    /// 版本号来自 Info.plist（build-app.sh 从仓库根目录的 VERSION 写入）；调试运行时没有
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "开发版"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Snug").font(.title.bold())
                Text(Self.version).foregroundStyle(.secondary)
            }
            Text("手机远程 Mac 的显示与触控增强")
            Link("github.com/zephyr4123/snug", destination: URL(string: "https://github.com/zephyr4123/snug")!)
            Divider()
            Text("致谢（MIT 许可）").font(.headline)
            ForEach(credits) { c in
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Link(c.name, destination: URL(string: c.url)!)
                    Text("· \(c.author) · \(c.usage)").foregroundStyle(.secondary)
                }
            }
            Text("社区 PR 作者：bubble、gencheng liu、Rongzheng Liu").foregroundStyle(.secondary)
            Divider()
            Text("本应用与 UU远程 及其开发商无任何关联")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 440, alignment: .leading)
    }
}

@MainActor
final class AboutWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: AboutView()))
            w.title = "关于 Snug"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            window = w
        }
        window?.center()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
