// 控制端设备的资料：类型与屏幕像素尺寸（用户在设置里填写）
import Foundation

/// CoreGraphics 的显示器编号（CGDirectDisplayID 的同义类型；SnugCore 不 import CoreGraphics）
public typealias DisplayID = UInt32

public enum DeviceKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case computer, tablet, phone

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .computer: "电脑"
        case .tablet: "平板"
        case .phone: "手机"
        }
    }
}

public struct DeviceProfile: Codable, Hashable, Identifiable, Sendable {
    public var name: String
    public var kind: DeviceKind
    /// 横屏原生像素；0 表示还没填
    public var width: Int
    public var height: Int
    public var hiDPI: Bool
    /// 从 UU「全部设备」导入时记下的分组与系统类型（按 UU 的样子分组、显示图标）
    public var uuComputer: Bool?
    public var platform: String?

    public init(name: String, kind: DeviceKind, width: Int, height: Int, hiDPI: Bool = true,
                uuComputer: Bool? = nil, platform: String? = nil) {
        self.name = name
        self.kind = kind
        self.width = width
        self.height = height
        self.hiDPI = hiDPI
        self.uuComputer = uuComputer
        self.platform = platform
    }

    public var id: String { name }
    public var inComputerGroup: Bool { uuComputer ?? (kind == .computer) }

    public static let validSize = 320...16384
    /// 宽高都在合理范围内才算填好
    public var hasSize: Bool { Self.validSize.contains(width) && Self.validSize.contains(height) }
    public var sizeLabel: String { "\(width)×\(height)\(hiDPI ? " 高清" : "")" }

    /// 显示规格相同（宽、高、高清）。名字不同但规格相同的两台设备可以共用同一块屏
    public func hasSameDisplaySpec(as other: DeviceProfile) -> Bool {
        width == other.width && height == other.height && hiDPI == other.hiDPI
    }

    private enum CodingKeys: String, CodingKey { case name, kind, width, height, hiDPI, uuComputer, platform }

    // hiDPI 缺省为 true：手填或旧格式的配置少这一项时不至于整份判为损坏
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        kind = try c.decode(DeviceKind.self, forKey: .kind)
        width = try c.decode(Int.self, forKey: .width)
        height = try c.decode(Int.self, forKey: .height)
        hiDPI = try c.decodeIfPresent(Bool.self, forKey: .hiDPI) ?? true
        uuComputer = try c.decodeIfPresent(Bool.self, forKey: .uuComputer)
        platform = try c.decodeIfPresent(String.self, forKey: .platform)
    }
}
