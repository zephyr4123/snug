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
               author: "AoyamaShou", usage: "Snug 承接自这个项目"),
        Credit(name: "PermissionFlow", url: "https://github.com/jaywcjlove/PermissionFlow",
               author: "小弟调调（jaywcjlove）", usage: "授权引导"),
        Credit(name: "TourKit", url: "https://github.com/rampatra/TourKit",
               author: "Ram Patra（rampatra）", usage: "功能导览"),
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
            Text("让用手机通过 UU远程 使用 Mac 更清晰、更方便。")
            Link("github.com/zephyr4123/snug", destination: URL(string: "https://github.com/zephyr4123/snug")!)
            Divider()
            Text("致谢（均为 MIT 许可）").font(.headline)
            ForEach(credits) { c in
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Link(c.name, destination: URL(string: c.url)!)
                    Text("· \(c.author) · \(c.usage)").foregroundStyle(.secondary)
                }
            }
            Text("以及社区 PR 的作者：bubble、gencheng liu、Rongzheng Liu。").foregroundStyle(.secondary)
            Divider()
            Text("本应用与 UU远程 及其开发商没有任何直接、间接或连带关系。")
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
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
