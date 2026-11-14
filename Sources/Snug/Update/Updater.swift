// 应用内更新：检查（每次启动一次，或用户点「检查更新」）和更新（用户点「立即更新」）。
// 更新按 UpdatePackage 的分块来：切开装着的 Snug.app，只取本机没有的块，在它旁边拼好新版本、核对签名和版本号，
// 和装着的原子对调，再走正常的退出收尾（窗口放回原处、撤掉手机屏），退出后由 AppBundle.relaunch 打开新版本。
// 下载、拼装期间出了任何错，装着的那个原样不动。进度和结果写在 AppState.update，「关于 Snug」和更新窗口读同一份
import AppKit
import SnugCore

struct UpdateState: Equatable {
    enum Check: Equatable {
        case unknown
        case upToDate
        /// 查到的比当前新的版本
        case available(UpdateFeed)
    }

    enum Phase: Equatable {
        case idle
        case checking
        /// 已取到的字节占要取的比例，0...1
        case downloading(Double)
        case installing
    }

    var check = Check.unknown
    var phase = Phase.idle
    /// 最近一次检查或更新没成的原因
    var problem: UpdateProblem?

    var available: UpdateFeed? {
        if case .available(let feed) = check { feed } else { nil }
    }

    /// 有新版本：能自动更新的，或者只能手动下载的（update.json 的格式比这一版新）
    var hasNewVersion: Bool { available != nil || problem == .tooOld }
}

/// 给用户看的失败原因：短词，不带技术细节（细节在日志里）
enum UpdateProblem: Error, Equatable {
    /// 网络不通，或者更新源上取不到、读不懂 update.json
    case unreachable(UpdateSource)
    case corrupt
    /// update.json 的格式比这一版新，这一版拼不出新版本
    case tooOld
    /// 应用包所在的位置换不了：写不进去（不在「应用程序」里、在只读的磁盘映像里），或者那块磁盘不支持原子对调
    case cannotReplace
    case signature
    case failed

    var text: String {
        switch self {
        case .unreachable(let source): "无法从\(source.title)获取更新"
        case .corrupt: "下载内容校验失败"
        case .tooOld: "新版本需手动下载"
        case .cannotReplace: "无法替换当前位置的 Snug"
        case .signature: "新版本签名不符"
        case .failed: "更新失败"
        }
    }

    /// 自动更新走不通，只能请用户去下载
    var needsDownload: Bool {
        switch self {
        case .tooOld, .cannotReplace, .signature: true
        case .unreachable, .corrupt, .failed: false
        }
    }
}

@MainActor
final class Updater {
    /// 正在运行的版本，来自 Info.plist（scripts/snug 打包时从 VERSION 写入）。开发时直接跑的没有，不检查更新
    nonisolated static let current = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
        .flatMap(Version.init)

    private let state: AppState
    private let client = UpdateClient()
    private let app = Bundle.main.bundleURL
    /// 查到了新版本。userInitiated：用户点的「检查更新」（启动时的检查不该抢走正在用的 App 的焦点）
    var onNewVersion: ((_ userInitiated: Bool) -> Void)?
    /// 换好了：交给退出流程
    var onInstalled: (() -> Void)?

    init(state: AppState) { self.state = state }

    private var busy: Bool { state.update.phase != .idle }

    /// 查一次有没有新版本。不轮询：启动时查一次，之后只有用户点了才查。
    /// waitForNetwork：开机自启时网可能还没起来，等它连上再问
    func check(userInitiated: Bool, waitForNetwork: Bool = false) {
        guard let current = Self.current, !busy else { return }
        let source = state.config.updateSource
        state.update.phase = .checking
        state.update.problem = nil
        Task {
            defer { state.update.phase = .idle }
            do {
                let feed = try await client.feed(from: source, waitForNetwork: waitForNetwork)
                Log.info("检查更新（\(source.title)）：最新 \(feed.version)，当前 \(current)")
                state.update.check = feed.version > current ? .available(feed) : .upToDate
            } catch {
                Log.warn("检查更新（\(source.title)）没成：\(error)")
                state.update.problem = Self.problem(for: error, source: source)
            }
            if state.update.hasNewVersion { onNewVersion?(userInitiated) }
        }
    }

    /// 用户点「立即更新」
    func install() {
        guard let feed = state.update.available, let current = Self.current, !busy else { return }
        let source = state.config.updateSource
        state.update.problem = nil
        state.update.phase = .downloading(0)
        Task {
            do {
                try await install(feed, from: source)
                Log.info("已更新 \(current) → \(feed.version)，退出后打开新版本")
                onInstalled?()
            } catch {
                Log.error("更新到 \(feed.version)（\(source.title)）没成：\(error)")
                state.update.problem = Self.problem(for: error, source: source)
                state.update.phase = .idle
            }
        }
    }

    private func install(_ feed: UpdateFeed, from source: UpdateSource) async throws {
        let app = app
        let folder = app.deletingLastPathComponent()
        let staged = folder.appendingPathComponent(".\(app.lastPathComponent).update")
        // 先看能不能换，换不了就别白下载。上次被打断（崩溃、关机）留下的暂存删不掉，同样换不了
        guard FileManager.default.isWritableFile(atPath: folder.path) else { throw UpdateProblem.cannotReplace }
        do { try Self.removeIfPresent(staged) } catch {
            Log.warn("上次留下的暂存删不掉（\(staged.path)）：\(error)")
            throw UpdateProblem.cannotReplace
        }

        let package = feed.package
        var chunks = try await Task.detached { try UpdatePackage.chunks(in: app) }.value
        let ranges = package.missingRanges(have: chunks)
        let total = ranges.reduce(0) { $0 + $1.count }
        Log.info("更新到 \(feed.version)：从\(source.title)取 \(ranges.count) 段共 \(total) 字节（包 \(package.file)），其余取自本机")
        var received = 0
        for range in ranges {
            let before = received
            let data = try await client.fetch(source.url(of: package.file, in: feed.version), range: range) { [weak self] bytes in
                self?.state.update.phase = .downloading(Double(before + bytes) / Double(max(total, 1)))
            }
            received += range.count
            chunks.merge(try package.unpack(data, at: range)) { $1 }
        }

        state.update.phase = .installing
        // 暂存目录从这里起由 defer 收：没换上时删的是拼好的新版本，换上之后删的是换下来的旧版本
        defer { Self.discard(staged) }
        try await Task.detached {
            try package.assemble(into: staged, from: chunks)
            try AppBundle.verifySignature(of: staged)
        }.value
        // 签名只证明出自同一开发者；还要是 update.json 说的那个版本，不然可能被换成签过名的旧版本
        let assembled = AppBundle.version(of: staged)
        guard assembled == feed.version else {
            throw UpdateError.corruptDownload("拼出来的是 \(assembled?.description ?? "-")，应为 \(feed.version)")
        }
        try AppBundle.swap(staged, app)
        try AppBundle.relaunch(app)
    }

    private static func removeIfPresent(_ url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    /// 删不掉不影响这次的结果，下次更新前会先删
    private static func discard(_ staged: URL) {
        do { try removeIfPresent(staged) } catch { Log.warn("暂存的应用包没删掉（\(staged.path)）：\(error)") }
    }

    private static func problem(for error: any Error, source: UpdateSource) -> UpdateProblem {
        switch error {
        case let problem as UpdateProblem: problem
        case UpdateError.newerFormat: .tooOld
        // malformed 只出自检查时解析 update.json：取到的读不懂，和取不到一样请用户换源或稍后再试
        case UpdateError.malformed, is URLError, is UpdateClientError: .unreachable(source)
        case is UpdateError: .corrupt
        case AppBundleError.signature: .signature
        case AppBundleError.swap: .cannotReplace
        default: .failed
        }
    }
}
