// 留下的账（见 LeftBehind）的主人：账本在内存里，落在 left-behind.json，改了就落盘。
// 记账（Desk 发现窗口在 Snug 之外没了）、认账（窗口原样回来、又放上屏）、还账（放回原位、缩回字号）都经它，
// 什么时候过期、改了怎么落盘只在这里定
import CoreGraphics
import Foundation

@MainActor
final class LeftBehindLedger {
    /// 这个窗口原样回来时欠着的那笔：改写好的还原记录，和认它用的那一笔（销账时按它找，不按下标：中间别的账可能已经销了）
    struct Owed {
        let record: PlacedRecord
        fileprivate let entry: LeftBehind
    }

    private(set) var book: LeftBehindBook
    private let file: JSONFile<LeftBehindBook>
    private let windows: any WindowControl
    private let apps: any AppControl

    init(url: URL, windows: any WindowControl, apps: any AppControl) {
        file = JSONFile(url: url)
        book = file.loadOrQuarantine() ?? LeftBehindBook()
        self.windows = windows
        self.apps = apps
    }

    var isEmpty: Bool { book.entries.isEmpty }

    // MARK: 记账

    /// 窗口在 Snug 之外没了：账不销，挂着等它带着屏上的大小回来再还。
    /// 字号按 App 存在哪处理：存在整个 App 里的（Zed）马上从它别的窗口缩回；会被 App 记住、回来时又认不出的（VS Code
    /// 按工作区记，重开时大小可能被重设），交回要给用户的提示
    func add(_ record: PlacedRecord) async -> Desk.Notice? {
        var record = record
        var notice: Desk.Notice?
        if record.zoom != 0 {
            switch ZoomBook.scope(of: record.bundleID) {
            case .app?:
                // 进程没了，内存里的字号跟着没了；还在就从它别的窗口缩回，没有别的窗口就留着，等它再出窗口时缩回
                if await !apps.isRunning(pid: record.window.pid) { record.zoom = 0 }
                else if await repayAppZoom(record) { record.zoom = 0 }
            case .workspace?:
                notice = .zoomLeftBehind(app: record.app, steps: record.zoom)
            case .liveWindow?, .restoredWindow?, nil:
                break
            }
        }
        book.add(LeftBehind(record: record, since: Date()))
        book.prune(now: Date())
        save()
        return notice
    }

    // MARK: 认账

    /// 这个窗口是不是哪一笔账的窗口原样回来了（同一个 App、带着 Snug 铺成的大小）
    func owed(by window: WindowInfo, frame: CGRect) -> Owed? {
        book.match(window, frame: frame).map { Owed(record: book.entries[$0].returned(as: window.key), entry: book.entries[$0]) }
    }

    /// 接着用这笔账放上屏了（Desk 把它写进了自己的还原账）：这边销掉
    func settle(_ owed: Owed) {
        guard let i = book.entries.firstIndex(of: owed.entry) else { return }
        book.remove(at: i)
        save()
    }

    // MARK: 还账

    /// 下一个原样回来了的窗口（skip 里的不算：各屏还放着的、还原账上还欠着的，归那本账还）。
    /// 先问窗口服务器（不经过 App，卡住的 App 也拖不慢队），大小对得上才去读辅助功能
    func nextReturn(skip: Set<WindowKey>) async -> (owed: Owed, window: WindowInfo, frame: CGRect)? {
        book.prune(now: Date())
        for bundle in Set(book.entries.compactMap(\.record.bundleID)) {
            for pid in await apps.pids(bundleID: bundle) {
                let sized = await windows.frames(of: pid).filter { !skip.contains($0.key) && book.awaits(bundleID: bundle, size: $0.value.size) }
                guard !sized.isEmpty else { continue }
                for window in await windows.shownWindows(of: pid) {
                    guard let frame = sized[window.key], let owed = owed(by: window, frame: frame) else { continue }
                    return (owed, window, frame)
                }
            }
        }
        return nil
    }

    /// 回来的窗口放回原位（to：换算成此刻坐标的原位），字号随窗口回来的一起缩回。还不成（App 没响应）留着，下一拍再试
    func repay(_ owed: Owed, window: WindowInfo, to original: CGRect) async {
        var entry = owed.entry
        if owed.record.zoom != 0 {
            guard await windows.restoreZoom(window.key, appliedSteps: owed.record.zoom) else {
                return Log.warn("\(window.label) 带着屏上的样子回来了，但字号缩不回（App 没响应），下一拍再试")
            }
            // 缩完先记账：挪的时候出事，下次不会再缩一遍
            entry = update(entry) { $0.record.zoom = 0 }
        }
        guard let got = await windows.move(window.key, to: original) else {
            return Log.warn("\(window.label) 带着屏上的样子回来了，但挪不动（App 没响应），下一拍再试")
        }
        settle(Owed(record: owed.record, entry: entry))
        Log.info("\(window.label) 带着屏上的样子回来了，放回原位 \(got.short)\(owed.record.zoom != 0 ? "，字号缩回 \(owed.record.zoom) 级" : "")")
    }

    /// 字号存在整个 App 里、还没缩回的（关窗时那个进程没有别的窗口）：进程又有窗口了就缩回，进程没了就不欠了
    func repayAppWideZoom() async {
        book.prune(now: Date())
        for entry in book.entries where entry.zoomScope == .app && entry.record.zoom != 0 {
            let r = entry.record
            if await apps.isRunning(pid: r.window.pid) {
                // 进程还在、还没有窗口就接着等（每拍都问，先看有没有窗口，免得每拍记一条日志）
                guard await !windows.shownWindows(of: r.window.pid).isEmpty, await repayAppZoom(r) else { continue }
            }
            update(entry) { $0.record.zoom = 0 }
        }
    }

    /// 字号存在整个 App 里（Zed）：从这个进程开着的另一个窗口缩回。没有别的窗口、或发不出去返回 false
    private func repayAppZoom(_ record: PlacedRecord) async -> Bool {
        guard let other = await windows.shownWindows(of: record.window.pid).first(where: { $0.key != record.window }) else {
            Log.info("\(record.label) 关了，\(record.app) 没有别的窗口，放大的 \(record.zoom) 级字号等它再出窗口时缩回")
            return false
        }
        let done = await windows.zoom(other.key, steps: -record.zoom)
        Log.info("\(record.label) 关了，字号存在整个 \(record.app) 里：从 \(other.label) 缩回 \(record.zoom) 级\(done ? "" : "，没发出去")")
        return done
    }

    /// 改一笔、落盘，交回改好的那笔（找不到就原样交回：已经销了）
    @discardableResult
    private func update(_ entry: LeftBehind, _ change: (inout LeftBehind) -> Void) -> LeftBehind {
        guard let i = book.entries.firstIndex(of: entry) else { return entry }
        book.update(at: i, change)
        save()
        return book.entries[i]
    }

    private func save() {
        do {
            try file.save(book)
        } catch {
            Log.error("留下的账写不进去（left-behind.json）：\(error)")
        }
    }
}
