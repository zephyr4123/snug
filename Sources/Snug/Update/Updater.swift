// 应用内更新：检查（每次启动一次，或用户点「检查更新」）和更新（用户点「立即更新」）。
// 更新按 UpdatePackage 的分块来：切开装着的 Snug.app，只取本机没有的块，在它旁边拼好新版本、核对签名，
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
}

/// 给用户看的失败原因：短词，不带技术细节（细节在日志里）
enum UpdateProblem: Equatable {
    case unreachable(UpdateSource)
    case corrupt
    /// update.json 的格式比这一版新，这一版拼不出新版本
    case tooOld
    /// 应用包所在的位置写不进去（不在「应用程序」里、在只读的磁盘映像里）
    case cannotReplace
    case signature
    case failed

    var text: String {
        switch self {
        case .unreachable(let source): "无法连接\(source.title)"
        case .corrupt: "下载内容校验失败"
        case .tooOld: "此版本无法自动更新"
        case .cannotReplace: "无权替换当前位置的 Snug"
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
    /// 正在运行的版本。开发时直接跑的（不在应用包里）没有版本号，不检查更新
    static let current = Version(AboutView.version)

    private let state: AppState
    private let client = UpdateClient()
    private let app = Bundle.main.bundleURL
    /// 查到了新版本：弹出更新窗口
    var onAvailable: (() -> Void)?
    /// 换好了：交给退出流程
    var onInstalled: (() -> Void)?

    init(state: AppState) { self.state = state }

    private var busy: Bool { state.update.phase != .idle }

    /// 启动时查一次。不轮询：开着的 Snug 不再查，下次启动才查
    func checkAtLaunch() { check(waitForNetwork: true) }

    /// 用户点「检查更新」
    func check() { check(waitForNetwork: false) }

    private func check(waitForNetwork: Bool) {
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
                if state.update.available != nil { onAvailable?() }
            } catch {
                Log.warn("检查更新（\(source.title)）没成：\(error)")
                state.update.problem = Self.problem(for: error, source: source)
            }
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
        let staged = app.deletingLastPathComponent().appendingPathComponent(".\(app.lastPathComponent).update")
        // 先看能不能换：换不了就别白下载
        guard FileManager.default.isWritableFile(atPath: app.deletingLastPathComponent().path) else {
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
        try await Task.detached {
            // 上次拼到一半被打断（崩溃、关机）留下的
            if FileManager.default.fileExists(atPath: staged.path) { try FileManager.default.removeItem(at: staged) }
            do {
                try package.assemble(into: staged, from: chunks)
                try AppBundle.verifySignature(of: staged)
            } catch {
                try? FileManager.default.removeItem(at: staged)
                throw error
            }
        }.value
        try AppBundle.swap(staged, app)
        // 对调之后 staged 那里是旧版本。删不掉不影响新版本，下次更新前会再删
        do { try FileManager.default.removeItem(at: staged) } catch { Log.warn("旧版本没删掉（\(staged.path)）：\(error)") }
        try AppBundle.relaunch(app)
    }

    private static func problem(for error: any Error, source: UpdateSource) -> UpdateProblem {
        switch error {
        case let problem as UpdateProblem: problem
        case is URLError, is UpdateClientError: .unreachable(source)
        case UpdateError.newerFormat: .tooOld
        case is UpdateError: .corrupt
        case AppBundleError.signature: .signature
        default: .failed
        }
    }
}

extension UpdateProblem: Error {}
