import CoreGraphics
import Foundation
@testable import SnugCore

/// 假屏幕和假窗口共用的流水账：检查动作的先后
final class Journal: Sendable {
    private let entries = Locked<[String]>([])
    func add(_ entry: String) { entries.withLock { $0.append(entry) } }
    var all: [String] { entries.withLock { $0 } }
    func clear() { entries.withLock { $0 = [] } }
    func index(of entry: String) -> Int? { all.firstIndex(of: entry) }
}

@MainActor
final class FakeDisplays: PhoneDisplays {
    let journal: Journal
    var nextID: DisplayID = 100
    /// 接下来这么多次建屏失败
    var failuresLeft = 0
    var hiDPI = true
    var screen = CGRect(x: 2000, y: 0, width: 540, height: 950)
    var area: CGRect? = CGRect(x: 2000, y: 25, width: 540, height: 897)
    /// 加屏、撤屏时 macOS 的副作用（把窗口拉过去、挪走）
    var onCreate: (() -> Void)?
    var onRetire: (() -> Void)?
    /// 记下建屏、撤屏的时刻（检查「建好不到 2.5 秒不撤」）
    var clock: (() -> TimeInterval)?
    private(set) var createdAt: [DisplayID: TimeInterval] = [:]
    private(set) var retiredAt: [DisplayID: TimeInterval] = [:]

    init(journal: Journal) { self.journal = journal }

    func create(_ spec: PhoneScreenSpec) async throws -> DisplayID {
        journal.add("create \(spec.orientation)")
        if failuresLeft > 0 {
            failuresLeft -= 1
            throw PhoneScreenError.neverOnline
        }
        nextID += 1
        createdAt[nextID] = clock?()
        onCreate?()
        return nextID
    }

    func retire(_ id: DisplayID) async {
        journal.add("retire \(id)")
        retiredAt[id] = clock?()
        onRetire?()
    }

    func ensureHiDPI(_ id: DisplayID, _ spec: PhoneScreenSpec) async -> Bool {
        journal.add("ensure \(id)")
        return hiDPI
    }

    func bounds(_ id: DisplayID) -> CGRect? { screen }
    func windowArea(_ id: DisplayID) -> CGRect? { area }
}

/// 假窗口：记住每个窗口的位置、是否全屏、是否最小化、字号级数
final class FakeWindows: WindowControl {
    struct Window: Sendable {
        var frame: CGRect
        var fullScreen = false
        var minimized = false
        var zoom = 0
    }

    let journal: Journal
    private let state = Locked<[WindowKey: Window]>([:])
    private let blocked = Locked(false)
    private let grows = Locked(false)
    private let moveHook = Locked<(@Sendable (WindowKey) -> Void)?>(nil)
    /// 设了就在每次挪窗口、发按键时记一下此刻还原记录在不在（检查「先记账再动手」）
    let ledger: URL?

    init(journal: Journal, ledger: URL? = nil) {
        self.journal = journal
        self.ledger = ledger
    }

    /// App 没响应（或辅助功能权限被收回）：窗口还在，但读不到、挪不动、发不了按键
    func block() { blocked.withLock { $0 = true } }
    /// 像终端那样：调字号时保持行列数，窗口跟着变大
    func growOnZoom() { grows.withLock { $0 = true } }
    /// 每次挪窗口前先调一下（检查挪的那一刻还原记录里写的是什么）
    func onMove(_ hook: @escaping @Sendable (WindowKey) -> Void) { moveHook.withLock { $0 = hook } }

    private var reachable: Bool { !blocked.withLock { $0 } }

    func add(_ key: WindowKey, frame: CGRect, fullScreen: Bool = false, minimized: Bool = false) {
        state.withLock { $0[key] = Window(frame: frame, fullScreen: fullScreen, minimized: minimized) }
    }

    func close(_ key: WindowKey) { _ = state.withLock { $0.removeValue(forKey: key) } }
    func window(_ key: WindowKey) -> Window? { state.withLock { $0[key] } }
    func setFrame(_ key: WindowKey, _ frame: CGRect) { state.withLock { $0[key]?.frame = frame } }

    private var mark: String {
        guard let ledger else { return "" }
        return FileManager.default.fileExists(atPath: ledger.path) ? " ✎" : " ∅"
    }

    func exists(_ window: WindowKey) async -> Bool { self.window(window) != nil }

    func look(_ window: WindowKey) async -> WindowLook? {
        guard reachable, let w = self.window(window) else { return nil }
        return WindowLook(frame: w.frame, fullScreen: w.fullScreen, minimized: w.minimized)
    }

    func move(_ window: WindowKey, to frame: CGRect) async -> CGRect? {
        guard reachable, self.window(window) != nil else { return nil }
        moveHook.withLock { $0 }?(window)
        journal.add("move \(window.id) \(frame.short)\(mark)")
        setFrame(window, frame)
        return frame
    }

    func setFullScreen(_ window: WindowKey, _ on: Bool) async {
        guard reachable else { return }
        journal.add("fullscreen \(window.id) \(on ? "on" : "off")")
        state.withLock { $0[window]?.fullScreen = on }
    }

    func setMinimized(_ window: WindowKey, _ on: Bool) async {
        guard reachable else { return }
        journal.add("minimize \(window.id) \(on ? "on" : "off")")
        state.withLock { $0[window]?.minimized = on }
    }

    func focus(_ window: WindowKey) async { journal.add("focus \(window.id)") }

    func zoom(_ window: WindowKey, steps: Int) async -> Bool {
        guard reachable, self.window(window) != nil else { return false }
        journal.add("zoom \(window.id) \(steps > 0 ? "+" : "")\(steps)\(mark)")
        let grow = grows.withLock { $0 }
        state.withLock {
            $0[window]?.zoom += steps
            if grow { $0[window]?.frame.size.width += CGFloat(steps * 50) }
        }
        return true
    }

    func snapshot() async -> [WindowKey: CGRect] {
        journal.add("snapshot")
        return state.withLock { $0.mapValues(\.frame) }
    }

    func restore(_ snapshot: [WindowKey: CGRect], except: WindowKey?) async {
        journal.add("restore" + (except.map { " except \($0.id)" } ?? ""))
        for (key, frame) in snapshot where key != except && self.window(key)?.frame != frame {
            setFrame(key, frame)
        }
    }
}

/// 不真等的时钟：sleep 直接把时间往前拨
final class ManualTimeline: Timeline {
    private let clock = Locked<TimeInterval>(1000)
    var now: TimeInterval { clock.withLock { $0 } }
    func advance(_ seconds: TimeInterval) { clock.withLock { $0 += seconds } }
    func sleep(_ seconds: TimeInterval) async {
        advance(seconds)
        await Task.yield()
    }
}
