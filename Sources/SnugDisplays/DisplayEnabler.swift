// 禁用 / 启用物理屏：CGSConfigureDisplayEnabled 私有接口。
// 实测（macOS 27）：禁用不受 .forAppOnly 约束，进程退出后不会自动恢复，必须由别的进程重新启用；
// 被禁用的屏会从在线列表里消失，所以禁用前必须先把 ID 写盘；
// 物理屏全禁用且虚拟屏也移除时，系统会生成一块 1920×1080 占位屏，按 ID 重新启用即可恢复
import CoreGraphics
import Foundation
import SnugCore

enum DisplayEnabler {
    typealias EnableFunction = @convention(c) (CGDisplayConfigRef?, CGDirectDisplayID, Bool) -> CGError

    private static let function: EnableFunction? =
        dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGSConfigureDisplayEnabled").map { unsafeBitCast($0, to: EnableFunction.self) }

    static var available: Bool { function != nil }

    /// 在一个事务里启用 / 禁用这些屏；任何一块设置失败都取消整个事务
    static func set(_ ids: [DisplayID], enabled: Bool) -> CGError {
        guard let function else { return .notImplemented }
        return applyDisplayConfig { config in
            for id in ids {
                let err = function(config, id, enabled)
                if err != .success { return err }
            }
            return .success
        }
    }
}
