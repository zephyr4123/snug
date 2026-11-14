// 设置、「关于 Snug」、更新窗口共用的搭法：SwiftUI 视图做内容，窗口高度跟着内容（提示出现、进度变化）自动变
import AppKit
import SwiftUI

extension NSWindow {
    convenience init(hosting view: some View, title: String, style: NSWindow.StyleMask = [.titled, .closable]) {
        let hosting = NSHostingController(rootView: view)
        hosting.sizingOptions = [.preferredContentSize]
        self.init(contentViewController: hosting)
        styleMask = style
        self.title = title
        isReleasedWhenClosed = false
        setContentSize(hosting.view.fittingSize)   // 先定尺寸再居中，否则按 0×0 居中会偏
        center()
    }

    /// 摆到最前。activating 为 false 时不激活 Snug：窗口照样浮在最前，但不抢走正在用的 App 的键盘焦点，
    /// 用户在别处按回车也不会误触窗口里的默认按钮（启动时的更新检查就这样弹）
    func present(activating: Bool) {
        if activating {
            NSApp.activate()
            makeKeyAndOrderFront(nil)
        } else {
            orderFrontRegardless()
        }
    }
}
