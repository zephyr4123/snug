// DisplayDriver 的 CoreGraphics 实现。
// - 建、释放虚拟屏在主线程同步做（与原版一致，原作者在这条路径上实测过）
// - 所有 CG 配置事务放在内部串行队列，完成后回主线程（GUI 主线程提交事务会与自己的重配置通知死锁）
import CGVirtualDisplayBridge
import CoreGraphics
import Foundation
import SnugCore

@MainActor
public final class CGDisplayDriver: DisplayDriver {
    private let queue = DispatchQueue(label: "com.zephyr4123.snug.display-config")
    private let ledger: PhysicalDisplayLedger
    private let layout: DisplayLayoutStore
    private var displays: [DisplayID: CGVirtualDisplay] = [:]

    public init(paths: SnugPaths) {
        ledger = PhysicalDisplayLedger(url: paths.disabledDisplays)
        layout = DisplayLayoutStore(url: paths.layout)
    }

    /// 熄灭物理屏用的私有接口是否可用
    public static var physicalControlAvailable: Bool { PhysicalDisplayLedger.available }

    // MARK: 查询

    public func onlineDisplays() -> [OnlineDisplay] {
        DisplayList.online().map { OnlineDisplay(id: $0, isSnugVirtual: DisplayList.isSnugVirtual($0)) }
    }

    public func disabledPhysicalDisplays() -> [DisplayID] { ledger.recorded() }

    public func hasLayoutSnapshot() -> Bool { layout.pending() != nil }

    // MARK: 动作

    public func captureLayout() throws {
        _ = try layout.captureAndSave()
    }

    public func createVirtual(_ request: VirtualDisplayRequest, completion: @escaping @MainActor @Sendable (VirtualCreateResult) -> Void) {
        let descriptor = CGVirtualDisplayDescriptor()
        descriptor.name = request.name
        descriptor.maxPixelsWide = UInt32(request.pixelWidth)
        descriptor.maxPixelsHigh = UInt32(request.pixelHeight)
        // 按 220 ppi 折算物理尺寸，只影响系统显示的英寸数
        descriptor.sizeInMillimeters = CGSize(width: Double(request.pixelWidth) / 220 * 25.4,
                                              height: Double(request.pixelHeight) / 220 * 25.4)
        descriptor.vendorID = VirtualDisplayIdentity.vendorID
        descriptor.productID = VirtualDisplayIdentity.productID
        descriptor.serialNum = request.serial

        // 同序列号的旧屏还在时返回 nil；不退回随机号（会多一个 ICC 文件），由执行器等旧屏下线
        guard let display = autoreleasepool(invoking: { CGVirtualDisplay(descriptor: descriptor) }) else {
            return completion(.failed("CGVirtualDisplay 返回 nil（serial=\(request.serial)）"))
        }
        let settings = CGVirtualDisplaySettings()
        settings.hiDPI = request.profile.hiDPI
        settings.modes = [CGVirtualDisplayMode(width: UInt(request.modeWidth), height: UInt(request.modeHeight), refreshRate: 60)]
        displays[display.displayID] = display
        let applied = autoreleasepool(invoking: { display.apply(settings) })
        completion(applied ? .created(display.displayID) : .applyFailed(display.displayID))
    }

    public func releaseVirtual(_ ids: [DisplayID], completion: @escaping @MainActor @Sendable () -> Void) {
        autoreleasepool {
            for id in ids where displays.removeValue(forKey: id) == nil {
                Log.warn("要释放的虚拟屏 #\(id) 不在本进程的记录里")
            }
        }
        completion()
    }

    public func setMain(_ id: DisplayID, completion: @escaping @MainActor @Sendable (TransactionOutcome) -> Void) {
        transaction(completion) {
            let target = CGDisplayBounds(id).origin
            return TransactionOutcome(applyDisplayConfig { config in
                for d in DisplayList.online() {
                    let o = CGDisplayBounds(d).origin
                    let err = CGConfigureDisplayOrigin(config, d, Int32(o.x - target.x), Int32(o.y - target.y))
                    if err != .success { return err }
                }
                return .success
            })
        }
    }

    public func disablePhysical(_ ids: [DisplayID], completion: @escaping @MainActor @Sendable (TransactionOutcome) -> Void) {
        let ledger = ledger
        transaction(completion) { ledger.disable(ids) }
    }

    public func enablePhysical(_ ids: [DisplayID], completion: @escaping @MainActor @Sendable (PhysicalRestoreResult) -> Void) {
        let ledger = ledger
        transaction(completion) { ledger.restore(ids) }
    }

    public func forgetDisabled(_ ids: [DisplayID]) throws {
        try ledger.forget(ids)
    }

    public func restoreModes(completion: @escaping @MainActor @Sendable (TransactionOutcome) -> Void) {
        let layout = layout
        transaction(completion) {
            guard let snapshot = layout.pending() else { return .success }
            return layout.restoreModes(snapshot)
        }
    }

    public func restoreOrigins(completion: @escaping @MainActor @Sendable (TransactionOutcome) -> Void) {
        let layout = layout
        transaction(completion) {
            guard let snapshot = layout.pending() else { return .success }
            return layout.restoreOrigins(snapshot)
        }
    }

    /// 在串行队列上做事务，结果回主线程
    private func transaction<R: Sendable>(_ completion: @escaping @MainActor @Sendable (R) -> Void,
                                          _ work: @escaping @Sendable () -> R) {
        queue.async {
            let result = work()
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(result) } }
        }
    }
}
