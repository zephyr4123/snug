import Foundation

/// 每个用例一个独立临时目录，用完删掉
struct TempDir: ~Copyable {
    let url: URL
    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("snug-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: url) }
}
