// --render-*：把界面渲染成 PNG 后退出。只构造视图和一份样例 AppState，
// 不建 AppController、不起感知器、不注册热键、不碰显示器（AppController.init 里有断言兜底）
import AppKit
import SwiftUI
import SnugCore
import TourKit

@MainActor
enum Renderer {
    /// 返回是否全部渲染成功
    static func run(_ target: RenderTarget, output dir: URL) -> Bool {
        NSApplication.shared.setActivationPolicy(.prohibited)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            print("❌ 建不了输出目录 \(dir.path)：\(error)")
            return false
        }
        let jobs: [(String, () -> Bool)]
        switch target {
        case .settings: jobs = RenderSamples.settings.map { s in (s.name, { snapshot(s.view(), dark: s.dark, to: dir, name: s.name) }) }
        case .permissions: jobs = RenderSamples.permissions.map { s in (s.name, { snapshot(s.view(), dark: s.dark, to: dir, name: s.name) }) }
        case .about: jobs = [false, true].map { dark in ("about", { snapshot(AboutView(), dark: dark, to: dir, name: dark ? "about-dark" : "about") }) }
        case .legacy: jobs = [("legacy", { snapshot(LegacyNoticeView(quitLegacy: {}, keepBoth: {}), dark: false, to: dir, name: "legacy") })]
        case .tourArtwork: jobs = TourArt.all.sorted { $0.key < $1.key }.map { name, view in (name, { image(view.frame(width: 800, height: 500), to: dir, name: name) }) }
        case .tourSlides(let images): jobs = tourSlides(images: images, to: dir)
        }
        var ok = true
        for (name, job) in jobs where !job() {
            print("❌ 渲染失败：\(name)")
            ok = false
        }
        return ok
    }

    private static func tourSlides(images: URL, to dir: URL) -> [(String, () -> Bool)] {
        let pages = Tour.tourPages(bundle: Bundle(url: images))
        return pages.indices.map { i in
            ("page-\(i + 1)", {
                let view = TourSlideshowView(pages: pages, width: Tour.width, initialPageIndex: i,
                                             continueButtonTitle: Tour.continueTitle, finishButtonTitle: Tour.finishTitle)
                    .environment(\.colorScheme, .dark)
                return image(view, to: dir, name: "page-\(i + 1)")
            })
        }
    }

    /// AppKit 控件（开关、分段选择、输入框）ImageRenderer 画不出来，用 NSHostingView 的 cacheDisplay，按 2 倍像素
    private static func snapshot(_ view: some View, dark: Bool, to dir: URL, name: String) -> Bool {
        let host = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        let size = host.bounds.size
        guard size.width > 0, size.height > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return false }
        rep.size = size
        host.cacheDisplay(in: host.bounds, to: rep)
        return write(rep.representation(using: .png, properties: [:]), to: dir, name: name)
    }

    /// 纯 SwiftUI 绘制（导览配图、导览页）用 ImageRenderer
    private static func image(_ view: some View, to dir: URL, name: String) -> Bool {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let cg = renderer.cgImage else { return false }
        return write(NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]), to: dir, name: name)
    }

    private static func write(_ png: Data?, to dir: URL, name: String) -> Bool {
        guard let png else { return false }
        let url = dir.appendingPathComponent("\(name).png")
        do {
            try png.write(to: url)
            print("✅ \(url.path)")
            return true
        } catch {
            print("❌ 写不进 \(url.path)：\(error)")
            return false
        }
    }
}

/// 渲染用的意图替身：什么都不做
@MainActor
final class RenderStub: AppIntents, Navigation {
    func setPaused(_ on: Bool) {}
    func setVirtualDisplayEnabled(_ on: Bool) {}
    func setKeepOnlyVirtual(_ on: Bool) {}
    func setWatchdogEnabled(_ on: Bool) {}
    func setLaunchAtLogin(_ on: Bool) {}
    func updateDevice(_ row: DeviceProfile) throws {}
    func importDevices() {}
    func restoreScreensNow() {}
    func restoreLayoutNow() {}
    func quitLegacyApp() {}
    func markTourShown() {}
    func quit() {}
    func openSettings(page: SettingsPage?) {}
    func openPermissions() {}
    func openTour() {}
    func openAbout() {}
}
