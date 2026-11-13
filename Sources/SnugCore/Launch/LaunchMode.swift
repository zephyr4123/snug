// 启动参数一次解析成启动模式，main.swift 只按模式组装。
// 只认双横线参数；单横线的（-psn_…、-AppleLanguages …）是系统或 Cocoa 塞进来的，忽略。
// 未知的双横线参数直接报错：拼错一个调试参数时宁可不启动，也不要悄悄按正常模式开始监控、动显示器
import Foundation

public enum RenderTarget: Equatable, Sendable {
    case settings
    case permissions
    case about
    /// 旧版共存提示
    case legacy
    /// 导览配图（Assets/Tour）
    case tourArtwork
    /// TourKit 导览界面逐页，配图取自 images
    case tourSlides(images: URL)
}

public enum LaunchMode: Equatable, Sendable {
    case app
    /// 看门狗（由 launchd 托管）
    case watchdog
    /// 只把界面渲染成 PNG
    case render(RenderTarget, output: URL)
    /// 打印从 UU 读到的设备、控制端
    case dumpUU
    /// 模拟一次连入 / 换设备 / 断开（不依赖 UU，会真的建虚拟屏）
    case simulate(names: [String], seconds: TimeInterval)
    /// 随机连入 / 换设备 / 断开压测（会真的建虚拟屏）
    case stress(rounds: Int, slow: Bool)

    /// 会不会改显示拓扑（建虚拟屏、熄灭或恢复物理屏）。渲染与 --dump-uu 保证不会
    public var touchesDisplays: Bool {
        switch self {
        case .app, .watchdog, .simulate, .stress: true
        case .render, .dumpUU: false
        }
    }

    public static let usage = """
    用法：Snug [模式]
      （无参数）                         正常启动
      --watchdog                         看门狗（由 launchd 托管）
      --render-settings <目录>            渲染设置窗口为 PNG
      --render-permissions <目录>         渲染权限窗口为 PNG
      --render-about <目录>               渲染「关于」窗口为 PNG
      --render-legacy <目录>              渲染旧版共存提示为 PNG
      --render-tour <目录>                渲染导览配图为 PNG（Assets/Tour）
      --render-tour-ui <配图目录> <目录>   渲染导览界面逐页为 PNG
      --dump-uu                          打印从 UU远程 读到的设备与控制端
      --simulate "<设备名>[>设备名]" [秒]   模拟一次远程（会真的建虚拟屏）
      --stress <轮数> [--slow]            随机连入断开压测（会真的建虚拟屏）
    """

    public static func parse(_ arguments: [String]) throws -> LaunchMode {
        var parser = Parser(arguments.filter { $0.hasPrefix("--") || !$0.hasPrefix("-") })
        var mode: (flag: String, value: LaunchMode)?
        var slow = false
        while let flag = parser.next() {
            guard flag.hasPrefix("--") else { continue }
            if flag == "--slow" { slow = true; continue }
            let value = try parser.mode(for: flag)
            if let first = mode { throw LaunchModeError.conflicting(first.flag, flag) }
            mode = (flag, value)
        }
        if case .stress(let rounds, _)? = mode?.value { return .stress(rounds: rounds, slow: slow) }
        return mode?.value ?? .app
    }
}

public enum LaunchModeError: Error, Equatable, Sendable, CustomStringConvertible {
    case unknownFlag(String)
    case missingValue(String)
    case invalidNumber(String, String)
    case conflicting(String, String)

    public var description: String {
        switch self {
        case .unknownFlag(let f): "不认识的参数 \(f)"
        case .missingValue(let f): "\(f) 缺少参数值"
        case .invalidNumber(let f, let v): "\(f) 的参数「\(v)」不是数字"
        case .conflicting(let a, let b): "\(a) 和 \(b) 不能一起用"
        }
    }
}

private struct Parser {
    private var rest: ArraySlice<String>

    init(_ arguments: [String]) { rest = arguments[...] }

    mutating func next() -> String? { rest.popFirst() }

    /// 下一个不是参数名的值
    private mutating func value(for flag: String) throws -> String {
        guard let v = rest.first, !v.hasPrefix("--") else { throw LaunchModeError.missingValue(flag) }
        rest.removeFirst()
        return v
    }

    private mutating func optionalValue() -> String? {
        guard let v = rest.first, !v.hasPrefix("--") else { return nil }
        rest.removeFirst()
        return v
    }

    mutating func mode(for flag: String) throws -> LaunchMode {
        let renders: [String: RenderTarget] = [
            "--render-settings": .settings, "--render-permissions": .permissions, "--render-about": .about,
            "--render-legacy": .legacy, "--render-tour": .tourArtwork,
        ]
        if let target = renders[flag] { return .render(target, output: URL(fileURLWithPath: try value(for: flag))) }
        switch flag {
        case "--watchdog":
            return .watchdog
        case "--dump-uu":
            return .dumpUU
        case "--render-tour-ui":
            let images = URL(fileURLWithPath: try value(for: flag))
            return .render(.tourSlides(images: images), output: URL(fileURLWithPath: try value(for: flag)))
        case "--simulate":
            let names = try value(for: flag).components(separatedBy: ">")
            guard let raw = optionalValue() else { return .simulate(names: names, seconds: 10) }
            guard let seconds = TimeInterval(raw), seconds > 0 else { throw LaunchModeError.invalidNumber(flag, raw) }
            return .simulate(names: names, seconds: seconds)
        case "--stress":
            let raw = try value(for: flag)
            guard let rounds = Int(raw), rounds > 0 else { throw LaunchModeError.invalidNumber(flag, raw) }
            return .stress(rounds: rounds, slow: false)
        default:
            throw LaunchModeError.unknownFlag(flag)
        }
    }
}
