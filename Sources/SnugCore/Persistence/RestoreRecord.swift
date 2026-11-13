// 可逆改动的记账：先记账、再改动、还原成功才销账。
// 记录写不进去就放弃这次改动；进程崩了，下次启动按记录还原
import Foundation

public struct RestoreRecord<Value: Codable>: Sendable {
    public let file: JSONFile<Value>

    public init(url: URL) { file = JSONFile(url: url) }

    /// 有待还原的记录就返回；损坏的记录隔离并记 error，按「没有记录」处理
    public func pending() -> Value? { file.loadOrQuarantine() }

    /// 先记账：写盘失败就抛错，调用方必须放弃这次改动
    public func record(_ value: Value) throws { try file.save(value) }

    /// 还原成功才销账
    public func settle() throws { try file.remove() }
}
