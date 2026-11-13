// 「关于」窗口：最简实现（原先依赖的 AboutKit 仓库已 404，无法再构建）。
// 第二阶段改写界面时再按 Snug 的设计重做；这里只保证名称、来源、致谢与免责声明齐全。
import AppKit
import SwiftUI

private struct AboutView: View {
    private struct Credit: Identifiable {
        let name, url, author, usage: String
        var id: String { name }
    }

    private let credits = [
        Credit(name: "UUyc-companion", url: "https://github.com/aoyamashou/UUyc-companion",
               author: "AoyamaShou", usage: "Snug 承接自该项目"),
        Credit(name: "FreeDisplay", url: "https://github.com/huberdf/FreeDisplay",
               author: "huberdf", usage: "虚拟屏接口声明"),
        Credit(name: "PermissionFlow", url: "https://github.com/jaywcjlove/PermissionFlow",
               author: "小弟调调（jaywcjlove）", usage: "授权引导"),
        Credit(name: "TourKit", url: "https://github.com/rampatra/TourKit",
               author: "Ram Patra（rampatra）", usage: "功能介绍页"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Snug").font(.title.bold())
            Text("让用手机通过 UU远程 使用 Mac 更清晰、更方便。")
            Link("https://github.com/zephyr4123/snug", destination: URL(string: "https://github.com/zephyr4123/snug")!)
            Divider()
            Text("致谢（均为 MIT 许可）").font(.headline)
            ForEach(credits) { c in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Link(c.name, destination: URL(string: c.url)!)
                    Text("· \(c.author) · \(c.usage)").foregroundStyle(.secondary)
                }
            }
            Divider()
            Text("本应用与 UU远程 及其开发商没有任何直接、间接或连带关系。")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 420, alignment: .leading)
    }
}

// 旧界面代码停在 Swift 5 语言模式、调用方没有标 @MainActor；这里只在主线程被调用
enum AboutPage {
    nonisolated(unsafe) private static var window: NSWindow?

    static func show() {
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

    /// 调试：渲染为 PNG（--render-about <文件>），不启动监控、不碰显示器
    @MainActor static func render(to url: URL) {
        let renderer = ImageRenderer(content: AboutView())
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
            Log.info("⚠️ 渲染关于窗口失败")
            return
        }
        do { try png.write(to: url) } catch { Log.info("⚠️ 写入关于窗口 PNG 失败：\(error)") }
    }
}
