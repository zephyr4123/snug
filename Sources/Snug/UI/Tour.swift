// 首次启动功能导览（TourKit）：5 页说明 + 配图。首次启动先看导览，再进授权引导与设置。
// 配图见 TourArt.swift；页面文案要和纲领一致：虚拟屏是可选功能，默认关闭
import AppKit
import SwiftUI
import TourKit

@MainActor
enum Tour {
    static let pages: [(image: String, title: LocalizedStringKey, description: LocalizedStringKey)] = [
        ("tour-welcome", "欢迎使用 Snug",
         "用手机通过 UU远程 使用这台 Mac 时，Snug 让画面更清晰、操作更顺手。"),
        ("tour-match", "可选：给手机准备一块虚拟屏",
         "按手机屏幕的分辨率新建虚拟屏，画面铺满、文字清晰。默认关闭，需要时在设置里打开。"),
        ("tour-physical", "远程时只保留虚拟屏",
         "熄灭其他屏幕，窗口不会跑到看不见的地方。打开虚拟屏之后才能用。"),
        ("tour-safety", "万一屏幕没亮，也能找回",
         "按 ⌃ control + ⌥ option + ⌘ command + 9 立即点亮所有屏幕；还可以打开看门狗自动兜底。"),
        ("tour-setup", "还差一步",
         "允许 Snug 读取 UU远程 里的设备名称。之后点菜单栏图标就能改设置。"),
    ]

    static let width: CGFloat = 660
    static let continueTitle: LocalizedStringKey = "继续"
    static let finishTitle: LocalizedStringKey = "开始设置"

    static func tourPages(bundle: Bundle?) -> [TourPage] {
        pages.map { TourPage(imageName: $0.image, imageBundle: bundle, title: $0.title, description: $0.description) }
    }
}

@MainActor
final class TourController {
    private let window = TourKitWindowController()

    /// 展示导览；关闭或看完都调用 onDone（只调一次）
    func show(onDone: (() -> Void)? = nil) {
        var called = false
        let done = {
            guard !called else { return }
            called = true
            onDone?()
        }
        window.present(pages: Tour.tourPages(bundle: .main), width: Tour.width,
                       continueButtonTitle: Tour.continueTitle, finishButtonTitle: Tour.finishTitle,
                       onFinish: done, onClose: done)
    }
}
