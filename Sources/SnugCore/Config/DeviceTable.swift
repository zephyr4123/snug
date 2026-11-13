// 设备表的编辑规则：按行校验、按行保存、从 UU「全部设备」导入。
// 按行保存是为了修 B10：旧版只要有一行没填完，整张表的修改都静默不存
import Foundation

/// 一行分辨率为什么不能保存
public enum DeviceSizeIssue: Error, Equatable, Sendable {
    /// 只填了宽或高
    case incomplete
    /// 不在 320...16384 之内
    case outOfRange

    public var message: String {
        switch self {
        case .incomplete: "宽和高都要填"
        case .outOfRange: "宽高要在 \(DeviceProfile.validSize.lowerBound)–\(DeviceProfile.validSize.upperBound) 之间"
        }
    }
}

public enum DeviceTableError: Error, Equatable, Sendable {
    case unknownDevice(String)
}

extension DeviceProfile {
    /// nil 表示这一行可以保存。电脑不用填尺寸；宽高都空表示「还没填」，可以保存，只是不会建虚拟屏
    public var sizeIssue: DeviceSizeIssue? {
        if kind == .computer || (width == 0 && height == 0) { return nil }
        if width == 0 || height == 0 { return .incomplete }
        return hasSize ? nil : .outOfRange
    }
}

extension AppConfig {
    /// 只替换同名的那一行；这一行无效就抛错，其余行不受影响
    public mutating func replaceDevice(_ row: DeviceProfile) throws {
        if let issue = row.sizeIssue { throw issue }
        guard let i = devices.firstIndex(where: { $0.name == row.name }) else {
            throw DeviceTableError.unknownDevice(row.name)
        }
        devices[i] = row
    }
}

/// 从 UU「全部设备」读到的一台设备
public struct UUDevice: Equatable, Sendable {
    public let name: String
    public let isComputerGroup: Bool
    /// 带「本机」标记，也就是这台 Mac 自己
    public let isSelf: Bool
    /// UU 图标里的系统类型：macos / ios / android / windows…
    public let platform: String

    public init(name: String, isComputerGroup: Bool, isSelf: Bool, platform: String) {
        self.name = name
        self.isComputerGroup = isComputerGroup
        self.isSelf = isSelf
        self.platform = platform
    }
}

public enum DeviceImport {
    /// 以 UU 的列表为准（按 UU 的顺序，不含本机）：已有设置保留，新设备按名字预填类型、尺寸留空
    public static func merge(found: [UUDevice], saved: [DeviceProfile]) -> [DeviceProfile] {
        found.filter { !$0.isSelf }.map { d in
            var row = saved.first { $0.name == d.name }
                ?? DeviceProfile(name: d.name, kind: .guess(name: d.name, isComputerGroup: d.isComputerGroup), width: 0, height: 0)
            row.uuComputer = d.isComputerGroup
            row.platform = d.platform
            return row
        }
    }
}
