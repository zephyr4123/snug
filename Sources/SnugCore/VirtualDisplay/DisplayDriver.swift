// 显示执行器的副作用接口。SnugDisplays 的 CGDisplayDriver 用 CoreGraphics 实现，测试里用假的。
// 约定：所有回调都回到主线程；CG 配置事务不在主线程执行（GUI 进程在主线程提交事务会与自己的重配置通知死锁），由实现负责
import Foundation

public struct OnlineDisplay: Equatable, Sendable {
    public let id: DisplayID
    /// 本工具建的虚拟屏（按厂商号识别）
    public let isSnugVirtual: Bool

    public init(id: DisplayID, isSnugVirtual: Bool) {
        self.id = id
        self.isSnugVirtual = isSnugVirtual
    }
}

/// 建一块虚拟屏需要的全部参数。只给一个显示模式，建好后不改（原作者实测：改模式会触发 WindowServer 重建模式列表）
public struct VirtualDisplayRequest: Equatable, Sendable {
    public let profile: DeviceProfile
    public let name: String
    public let serial: UInt32

    public init(profile: DeviceProfile) {
        self.profile = profile
        name = VirtualDisplayIdentity.name(for: profile)
        serial = VirtualDisplayIdentity.serial(for: profile)
    }

    public var pixelWidth: Int { profile.width }
    public var pixelHeight: Int { profile.height }
    /// 唯一的显示模式（逻辑点）：高清时是像素的一半
    public var modeWidth: Int { profile.hiDPI ? profile.width / 2 : profile.width }
    public var modeHeight: Int { profile.hiDPI ? profile.height / 2 : profile.height }
}

public enum DisplayFailure: Error, Equatable, Sendable, CustomStringConvertible {
    /// CG 事务返回的 CGError 原始值
    case cgError(Int32)
    /// 记录写不进磁盘（先记账失败，改动没有发生）
    case recordFailed(String)
    /// 私有接口不可用等
    case unavailable(String)

    /// 1004 = kCGErrorCannotComplete；1014 是原作者实测到的事务超时。出现即说明 WindowServer 显示配置已卡死
    public var isWedge: Bool {
        if case .cgError(let code) = self { return code == 1004 || code == 1014 }
        return false
    }

    public var description: String {
        switch self {
        case .cgError(let code): "CGError=\(code)"
        case .recordFailed(let why): "记录写入失败：\(why)"
        case .unavailable(let why): why
        }
    }
}

public enum TransactionOutcome: Equatable, Sendable {
    case success
    case failure(DisplayFailure)

    public var failure: DisplayFailure? {
        if case .failure(let f) = self { return f }
        return nil
    }
}

public enum VirtualCreateResult: Equatable, Sendable {
    case created(DisplayID)
    /// 屏建出来了但 applySettings 失败：不能立即释放（立即释放曾让 WindowServer 崩溃），要稳定后再放
    case applyFailed(DisplayID)
    /// CGVirtualDisplay 返回 nil（例如同序列号的旧屏还在）
    case failed(String)
}

public struct PhysicalRestoreResult: Equatable, Sendable {
    /// 已恢复（含本来就已亮着的），已从记录里移除
    public var restored: [DisplayID]
    public var failed: [DisplayID]
    public var failure: DisplayFailure?

    public init(restored: [DisplayID], failed: [DisplayID], failure: DisplayFailure?) {
        self.restored = restored
        self.failed = failed
        self.failure = failure
    }
}

@MainActor
public protocol DisplayDriver: AnyObject {
    /// 当前在线的显示器（被禁用的物理屏不在其中）
    func onlineDisplays() -> [OnlineDisplay]
    /// 磁盘上记录的「已禁用、待恢复」物理屏。以磁盘为准：看门狗等别的进程可能已经恢复并删了记录
    func disabledPhysicalDisplays() -> [DisplayID]
    /// 磁盘上是否有布局快照
    func hasLayoutSnapshot() -> Bool

    /// 采集物理屏布局并写进 layout.json（不改拓扑）。写不进去就抛错，调用方放弃本次建屏
    func captureLayout() throws
    func createVirtual(_ request: VirtualDisplayRequest, completion: @escaping @MainActor @Sendable (VirtualCreateResult) -> Void)
    func releaseVirtual(_ ids: [DisplayID], completion: @escaping @MainActor @Sendable () -> Void)
    /// 把这块屏放到 (0,0) 成为主屏，其余屏相对平移
    func setMain(_ id: DisplayID, completion: @escaping @MainActor @Sendable (TransactionOutcome) -> Void)
    /// 先把 ID 写进记录，再禁用；事务失败时把刚加的 ID 从记录里撤掉
    func disablePhysical(_ ids: [DisplayID], completion: @escaping @MainActor @Sendable (TransactionOutcome) -> Void)
    /// 在一个事务里启用这些屏；成功的从记录里移除，记录空了就删文件
    func enablePhysical(_ ids: [DisplayID], completion: @escaping @MainActor @Sendable (PhysicalRestoreResult) -> Void)
    /// 放弃恢复这些屏（多半已被拔掉），从记录里删掉
    func forgetDisabled(_ ids: [DisplayID]) throws
    /// 按快照恢复各屏的显示模式（一个事务；当前模式已对的跳过）
    func restoreModes(completion: @escaping @MainActor @Sendable (TransactionOutcome) -> Void)
    /// 按快照恢复各屏原点（一个事务）；成功后删掉快照
    func restoreOrigins(completion: @escaping @MainActor @Sendable (TransactionOutcome) -> Void)
}
