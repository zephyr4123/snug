// 虚拟屏功能模块的入口：把会话层的变化和用户设置翻译成显示执行器的目标。
// 可选功能，默认关闭。会话层不知道它的存在：App 层每拍把 RemoteSession 的变化交给它即可
import Foundation

@MainActor
public final class VirtualDisplayFeature {
    public struct Settings: Equatable, Sendable {
        public var enabled: Bool
        public var paused: Bool
        public var keepOnlyVirtual: Bool
        /// 熄灭物理屏用的私有接口是否可用
        public var physicalControlAvailable: Bool
        public var devices: [DeviceProfile]

        public init(config: AppConfig, physicalControlAvailable: Bool) {
            enabled = config.virtualDisplayEnabled
            paused = config.paused
            keepOnlyVirtual = config.keepOnlyVirtual
            self.physicalControlAvailable = physicalControlAvailable
            devices = config.devices
        }
    }

    public let executor: DisplayExecutor
    public private(set) var settings: Settings
    public private(set) var breaker = PhysicalOffBreaker()

    public init(executor: DisplayExecutor, settings: Settings) {
        self.executor = executor
        self.settings = settings
    }

    /// 每拍调用（transitions 可以为空）：先更新熔断，再按当前会话状态重算目标
    public func handle(_ transitions: [SessionTransition], session: RemoteSession) {
        for t in transitions {
            // 断开时要在恢复物理屏之前读「物理屏是否关着」
            breaker.handle(t, physicalOff: executor.physicalOff)
        }
        applyTarget(session: session)
    }

    public func update(settings: Settings, session: RemoteSession) {
        self.settings = settings
        applyTarget(session: session)
    }

    /// 热键 / 菜单「立即恢复物理屏」。调用前 App 层先 session.suspendByUser()：
    /// 会话中则本会话不再熄屏；不在会话中只恢复这一下，不影响下一次远程
    public func userRequestedRestore(session: RemoteSession) {
        applyTarget(session: session)
        executor.restorePhysicalNow()
    }

    private func applyTarget(session: RemoteSession) {
        executor.setTarget(profile: profile(for: session), keepOnlyVirtual: keepOnlyVirtual(session: session))
    }

    /// 只处理设备列表里、填了分辨率的平板和手机；读不到名字或认不出就不调整，交给 UU远程 自己处理
    private func profile(for session: RemoteSession) -> DeviceProfile? {
        guard settings.enabled, !settings.paused, session.isConnected,
              let name = session.controller,
              let p = settings.devices.first(where: { $0.name == name }),
              p.kind != .computer, p.hasSize else { return nil }
        return p
    }

    private func keepOnlyVirtual(session: RemoteSession) -> Bool {
        settings.keepOnlyVirtual && settings.physicalControlAvailable && breaker.allowsPhysicalOff && !session.suspendedByUser
    }
}
