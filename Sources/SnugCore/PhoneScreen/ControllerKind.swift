// 控制端是什么设备：只看 UU 表格里的名字。手机、平板才加手机屏；电脑控制端不加。
// 名字读不到（UU 主窗口没开时就读不到）或认不出时按手机处理：手机屏只是 UU 里多一个可选项，
// 用不用由用户决定，宁可多给，不要让手机用户等不到
import Foundation

public enum ControllerKind: Equatable, Sendable {
    case mobile, computer, unknown

    private static let mobileHints = ["iphone", "ipad", "android", "phone", "pad", "手机", "平板"]
    /// Windows 默认的机器名是 DESKTOP-xxxx / LAPTOP-xxxx；Mac 的名字里带 Mac（MacBook、iMac、Mac mini）
    private static let computerHints = ["mac", "desktop-", "laptop-", "pc", "windows", "电脑", "笔记本", "台式"]

    public init(name: String?) {
        guard let n = name?.lowercased(), !n.isEmpty else {
            self = .unknown
            return
        }
        if Self.mobileHints.contains(where: n.contains) {
            self = .mobile
        } else if Self.computerHints.contains(where: n.contains) {
            self = .computer
        } else {
            self = .unknown
        }
    }

    public var wantsPhoneScreen: Bool { self != .computer }
}
