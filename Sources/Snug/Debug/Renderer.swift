// --render-*：把界面渲染成 PNG 后退出。只构造视图和一份样例 AppState，
// 不建 AppController、不起感知器、不碰屏幕和窗口
import AppKit
import SwiftUI
import SnugCore

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
        var ok = true
        for sample in RenderSamples.samples(for: target) where !snapshot(sample, to: dir) {
            print("❌ 渲染失败：\(sample.name)")
            ok = false
        }
        return ok
    }

    /// AppKit 控件（开关、步进器）ImageRenderer 画不出来，用 NSHostingView 的 cacheDisplay，按 2 倍像素
    private static func snapshot(_ sample: RenderSample, to dir: URL) -> Bool {
        let host = NSHostingView(rootView: sample.view().background(Color(nsColor: .windowBackgroundColor)))
        host.appearance = NSAppearance(named: sample.dark ? .darkAqua : .aqua)
        host.frame = NSRect(origin: .zero, size: sample.size ?? host.fittingSize)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        let size = host.bounds.size
        guard size.width > 0, size.height > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return false }
        rep.size = size
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return false }
        let url = dir.appendingPathComponent("\(sample.name).png")
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
final class RenderStub: AppIntents, PhoneIntents, Navigation {
    func setPhoneScreen(_ on: Bool) {}
    func setGestures(_ on: Bool) {}
    func setZoomSteps(_ steps: Int) {}
    func setLaunchAtLogin(_ on: Bool) {}
    func markWelcomed() {}
    func quitLegacyApp() {}
    func quit() {}
    func pull(_ window: WindowInfo) {}
    func showList() {}
    func returnToPlaced() {}
    func putBack() {}
    func rotate() {}
    func zoom(by delta: Int) {}
    func openSettings() {}
    func openWelcome() {}
    func openAbout() {}
}
