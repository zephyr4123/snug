// --render-*：把界面渲染成 PNG 后退出。只构造视图和一份样例 AppState，
// 不建 AppController、不起远控适配器、不碰屏幕和窗口
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
        let frame = NSRect(origin: .zero, size: sample.size ?? host.fittingSize)
        // 列表（NSTableView）没有窗口不排行，要挂进一个不显示的窗口；挂了窗口控件按「窗口不在前台」画成灰的，所以只给要的样例挂
        var window: NSWindow?
        if sample.inWindow {
            window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window?.isReleasedWhenClosed = false
            window?.contentView = host
        }
        defer { window?.close() }
        host.frame = frame
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
final class RenderStub: AppIntents, TouchIntents, Navigation {
    func setScreenEnabled(_ id: ScreenID, _ on: Bool) {}
    func addScreen(orientation: Orientation, device: DeviceChoice, name: String) {}
    func removeScreen(_ id: ScreenID) {}
    func setScreenDevice(_ id: ScreenID, _ device: DeviceChoice) {}
    func setScreenResolution(_ id: ScreenID, width: Int?) {}
    func renameScreen(_ id: ScreenID, _ name: String) {}
    func setMainScreen(_ id: ScreenID?) {}
    func setGestures(_ on: Bool) {}
    func setZoomSteps(_ steps: Int) {}
    func setLaunchAtLogin(_ on: Bool) {}
    func openLoginItemsSettings() {}
    func markWelcomed() {}
    func quitLegacyApp() {}
    func endSessionNow() {}
    func quit() {}
    func checkForUpdates() {}
    func installUpdate() {}
    func setUpdateSource(_ source: UpdateSource) {}
    func openDownloadPage() {}
    func setScreenshot(_ on: Bool) {}
    func pull(_ window: WindowInfo) {}
    func open(_ app: AppInfo) {}
    func newWindow(_ app: RunningApp) {}
    func quit(_ app: RunningApp) {}
    func forceQuit(pid: Int32, app: String) {}
    func close(_ window: WindowInfo) {}
    func dismissNotice() {}
    func showList() {}
    func returnToPlaced() {}
    func putBack() {}
    func putBack(_ window: WindowKey) {}
    func zoom(by delta: Int) {}
    func setDevice(_ device: DeviceChoice) {}
    func dismissScreen() {}
    func cancelMain() {}
    func takeScreenshot() {}
    func openCrop() {}
    func cancelCrop() {}
    func finishCrop(_ selection: CGRect) {}
    func openSettings(on display: DisplayID?) {}
    func openWelcome() {}
    func openAbout(on display: DisplayID?) {}
    func openUpdate() {}
    func openLibrary(on display: DisplayID?) {}
}
