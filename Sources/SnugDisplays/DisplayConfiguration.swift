// CoreGraphics 显示配置的公用小件：配置事务、在线列表、本工具虚拟屏的识别
import CoreGraphics
import SnugCore

/// 同步执行一次显示配置事务（.forSession）。body 返回非 success 时取消事务并返回该错误；提交失败也取消并返回错误码，不吞。
/// GUI 进程里不能在主线程调用：会与自己的重配置通知死锁
@discardableResult
public func applyDisplayConfig(_ body: (CGDisplayConfigRef?) -> CGError) -> CGError {
    var config: CGDisplayConfigRef?
    let begin = CGBeginDisplayConfiguration(&config)
    guard begin == .success else { return begin }
    let staged = body(config)
    guard staged == .success else {
        CGCancelDisplayConfiguration(config)
        return staged
    }
    let err = CGCompleteDisplayConfiguration(config, .forSession)
    if err != .success { CGCancelDisplayConfiguration(config) }
    return err
}

public enum DisplayList {
    public static func online() -> [DisplayID] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }

    public static func isSnugVirtual(_ id: DisplayID) -> Bool {
        CGDisplayVendorNumber(id) == VirtualDisplayIdentity.vendorID
    }

    /// 明确在线且已启用（查询失败时 CG 可能返回 -1，只认 1）
    public static func isOnlineAndActive(_ id: DisplayID) -> Bool {
        CGDisplayIsOnline(id) == 1 && CGDisplayIsActive(id) == 1
    }
}

extension TransactionOutcome {
    init(_ err: CGError) {
        self = err == .success ? .success : .failure(.cgError(err.rawValue))
    }
}
