// 和更新源打交道：取 update.json，按字节范围从包里取块。只用 URLSession，代理、证书都跟着系统走
import Foundation
import SnugCore

struct UpdateClient: Sendable {
    /// 用户点「检查更新」：没网就当场说
    private static let immediate = URLSession(configuration: configuration(waitForNetwork: false))
    /// 启动时顺带查：开机时网可能还没起来，等它连上再问
    private static let patient = URLSession(configuration: configuration(waitForNetwork: true))

    private static func configuration(waitForNetwork: Bool) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = waitForNetwork
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = waitForNetwork ? 120 : 60
        return configuration
    }

    /// 最新发布的 update.json，跳过本地缓存（国内源那边只缓存 5 分钟，GitHub 那边是跳转）
    func feed(from source: UpdateSource, waitForNetwork: Bool) async throws -> UpdateFeed {
        let request = URLRequest(url: source.feedURL, cachePolicy: .reloadIgnoringLocalCacheData)
        let (data, response) = try await (waitForNetwork ? Self.patient : Self.immediate).data(for: request)
        try Self.expect(response, 200)
        return try UpdateFeed.decode(data)
    }

    /// 取 url 这个文件里 range 那一段。每收到一些就报一次这一段已经收到多少字节
    func fetch(_ url: URL, range: Range<Int>, progress: @escaping @MainActor (Int) -> Void) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("bytes=\(range.lowerBound)-\(range.upperBound - 1)", forHTTPHeaderField: "Range")
        let (bytes, response) = try await Self.immediate.bytes(for: request)
        // GitHub（跟着跳转到存放附件的地方）和国内源都按字节范围回 206；不认字节范围的当成取不到
        try Self.expect(response, 206)
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count % 65_536 == 0 { await progress(data.count) }
        }
        await progress(data.count)
        return data
    }

    private static func expect(_ response: URLResponse, _ status: Int) throws {
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == status else { throw UpdateClientError.status(code, response.url) }
    }
}

enum UpdateClientError: Error, CustomStringConvertible {
    case status(Int, URL?)

    var description: String {
        switch self {
        case .status(let code, let url): "HTTP \(code)（\(url?.absoluteString ?? "-")）"
        }
    }
}
