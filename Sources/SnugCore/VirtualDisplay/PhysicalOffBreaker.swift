// 熄屏不稳定熔断（虚拟屏模块自己的策略）。
// 某次断开发生时物理屏是关着的（于是去恢复了物理屏），而重连窗口内又连上了——说明熄灭物理屏扰乱了 UU 的信号，
// 再关下去就是 2026-11-12 19:01 那种「关屏 → 误判断开 → 开屏 → 重连 → 再关屏」的振荡。
// 判定后本会话不再关物理屏，会话结束复位
import Foundation

public struct PhysicalOffBreaker: Sendable {
    public private(set) var tripped = false
    private var interruptedWhilePhysicalOff = false

    public init() {}

    public var allowsPhysicalOff: Bool { !tripped }

    /// physicalOff：此刻物理屏是否关着（断开时要在恢复之前读）
    public mutating func handle(_ transition: SessionTransition, physicalOff: Bool) {
        switch transition {
        case .began, .ended:
            tripped = false
            interruptedWhilePhysicalOff = false
        case .interrupted:
            interruptedWhilePhysicalOff = physicalOff
        case .resumed:
            if interruptedWhilePhysicalOff, !tripped {
                tripped = true
                Log.warn("熄屏不稳定：物理屏关着时断开、重连窗口内又连上，本次远程不再熄灭物理屏")
            }
            interruptedWhilePhysicalOff = false
        case .controllerChanged:
            break
        }
    }
}
