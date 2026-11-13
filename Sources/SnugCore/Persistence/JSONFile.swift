// 一个 JSON 状态文件的读写。读取结果区分「不存在 / 损坏 / 成功」，写和删失败都抛错，不吞
import Foundation

public enum JSONFileContent<Value> {
    case missing
    /// 读不出来或解不开都算损坏
    case corrupt(any Error)
    case loaded(Value)
}

public struct JSONFile<Value: Codable>: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    public func load() -> JSONFileContent<Value> {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return .missing
        } catch {
            return .corrupt(error)
        }
        do {
            return .loaded(try Self.decoder.decode(Value.self, from: data))
        } catch {
            return .corrupt(error)
        }
    }

    /// 原子写入；父目录不存在就建
    public func save(_ value: Value) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.encoder.encode(value).write(to: url, options: .atomic)
    }

    /// 文件本来就不存在不算失败；存在却删不掉要抛错
    public func remove() throws {
        do {
            try FileManager.default.removeItem(at: url)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            return
        }
    }

    /// 把损坏的文件改名成 <name>.corrupt-<时间戳>.json 留作排查，原位置空出来给默认值用
    @discardableResult
    public func quarantine(now: Date = Date()) throws -> URL {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss-SSS"
        let base = url.deletingPathExtension().lastPathComponent
        let target = url.deletingLastPathComponent().appendingPathComponent("\(base).corrupt-\(f.string(from: now)).json")
        try FileManager.default.moveItem(at: url, to: target)
        return target
    }

    /// 调用方最常用的读法：不存在返回 nil；损坏时隔离原文件、记 error，再返回 nil 让调用方用默认值。
    /// 隔离失败也记 error（原文件留在原处，下次还会再试），绝不用默认值覆盖原内容
    public func loadOrQuarantine(now: Date = Date()) -> Value? {
        switch load() {
        case .missing:
            return nil
        case .loaded(let value):
            return value
        case .corrupt(let error):
            do {
                let moved = try quarantine(now: now)
                Log.error("\(url.lastPathComponent) 已损坏（\(error)），原文件改名为 \(moved.lastPathComponent)，改用默认值")
            } catch let moveError {
                Log.error("\(url.lastPathComponent) 已损坏（\(error)），改名隔离也失败（\(moveError)），本次改用默认值")
            }
            return nil
        }
    }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
