// 控制端是什么设备：只看 UU 表格里的名字。手机、平板才加手机屏；电脑控制端不加。
// 表格没给出名字（读不到，或没认出控制端行）、名字认不出是什么设备时，都按手机处理：手机屏只是 UU 里多一个可选项，
// 用不用由用户决定，宁可多给，不要让手机用户等不到
import Foundation

public enum ControllerKind: Equatable, Sendable {
    case mobile, computer, unknown

    /// 刚连上时控制端表格要慢一两拍才读到（后台读）：名字还没读到时先等这么久再按手机处理，
    /// 免得电脑控制端连上的那一拍先加了手机屏、下一拍读到名字又撤掉
    public static let nameGrace: TimeInterval = 2

    private static let mobileHints = ["iphone", "ipad", "matepad", "android", "phone", "手机", "平板"]
    /// 单独成词的「pad」才算平板（OPPO Pad、Xiaomi Pad）：ThinkPad 是笔记本
    private static let tabletWord = "pad"
    /// Windows 默认的机器名是 DESKTOP-xxxx / LAPTOP-xxxx；Mac 的名字里带 Mac（MacBook、iMac、Mac mini）；
    /// 国产和其它品牌的笔记本常用出厂名（HUAWEI MateBook、HONOR MagicBook、RedmiBook、Galaxy Book、Surface）
    private static let computerHints = ["mac", "desktop-", "thinkpad", "pc", "windows", "matebook", "magicbook", "redmibook",
                                        "xiaomi book", "galaxy book", "surface", "电脑", "笔记本", "台式"]
    /// 单独成词才算（LAPTOP-AB12、Surface Laptop 5）
    private static let computerWords: Set<Substring> = ["laptop", "notebook"]

    public init(name: String?) {
        guard let n = name?.lowercased(), !n.isEmpty else {
            self = .unknown
            return
        }
        let words = n.split { !$0.isLetter && !$0.isNumber }
        if Self.mobileHints.contains(where: n.contains) || words.contains(Substring(Self.tabletWord)) {
            self = .mobile
        } else if Self.computerHints.contains(where: n.contains) || words.contains(where: Self.computerWords.contains) {
            self = .computer
        } else {
            self = .unknown
        }
    }

    public var wantsPhoneScreen: Bool { self != .computer }
}

extension RemoteSession {
    /// 这次远程要不要手机屏：在一次远程里（断开重连的窗口内也算），控制端不是电脑。
    /// 按整次远程记住的名字判断：断开那一拍名字被清空，不能因此把电脑控制端当成手机
    public func wantsPhoneScreen(now: Date) -> Bool {
        guard let began = episodeBeganAt else { return false }
        if episodeController == nil, now.timeIntervalSince(began) < ControllerKind.nameGrace { return false }
        return ControllerKind(name: episodeController).wantsPhoneScreen
    }
}
