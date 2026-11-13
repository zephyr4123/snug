// 屏幕查找与坐标换算。AppKit（NSScreen、窗口）用左下原点，辅助功能和 CGEvent 用主屏左上原点
import AppKit
import SnugCore

@MainActor
public enum Screens {
    public static func screen(for id: DisplayID) -> NSScreen? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return NSScreen.screens.first { ($0.deviceDescription[key] as? NSNumber)?.uint32Value == id }
    }

    /// 在「显示器」设置里的名字；找不到就用编号
    public static func name(of id: DisplayID) -> String {
        screen(for: id)?.localizedName ?? "显示器 #\(id)"
    }

    /// AppKit 坐标 → 辅助功能坐标
    public static func axRect(fromAppKit rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// 主屏（菜单栏所在、原点为 0,0 的那块）的高度
    private static var primaryHeight: CGFloat {
        (NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.screens.first)?.frame.height ?? 0
    }
}
