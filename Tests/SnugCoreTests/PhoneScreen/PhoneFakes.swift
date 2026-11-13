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
    var createFails = false
    var hiDPI = true
    var area = CGRect(x: 2000, y: 25, width: 540, height: 897)
    /// 加屏时 macOS 的副作用（比如把上次留在这块屏上的窗口拉过去）
    var onCreate: (() -> Void)?

    init(journal: Journal) { self.journal = journal }

    func create(_ spec: PhoneScreenSpec) async throws -> DisplayID {
        journal.add("create \(spec.orientation)")
        if createFails { throw PhoneScreenError.neverOnline }
        nextID += 1
        onCreate?()
        return nextID
    }

    func retire(_ id: DisplayID) async { journal.add("retire \(id)") }

    func ensureHiDPI(_ id: DisplayID, _ spec: PhoneScreenSpec) async -> Bool {
        journal.add("ensure \(id)")
        return hiDPI
    }

    func windowArea(_ id: DisplayID) -> CGRect? { area }
}

/// 假窗口：记住每个窗口的位置、是否全屏、字号级数
final class FakeWindows: WindowControl {
    struct Window: Sendable {
        var frame: CGRect
        var fullScreen = false
        var zoom = 0
    }

    let journal: Journal
    private let state = Locked<[WindowKey: Window]>([:])
    /// 设了就在每次挪窗口、发按键时记一下此刻还原记录在不在（检查「先记账再动手」）
    let ledger: URL?

    init(journal: Journal, ledger: URL? = nil) {
        self.journal = journal
        self.ledger = ledger
    }

    func add(_ key: WindowKey, frame: CGRect, fullScreen: Bool = false) {
        state.withLock { $0[key] = Window(frame: frame, fullScreen: fullScreen) }
    }

    func close(_ key: WindowKey) { _ = state.withLock { $0.removeValue(forKey: key) } }
    func window(_ key: WindowKey) -> Window? { state.withLock { $0[key] } }
    func setFrame(_ key: WindowKey, _ frame: CGRect) { state.withLock { $0[key]?.frame = frame } }

    private var mark: String {
        guard let ledger else { return "" }
        return FileManager.default.fileExists(atPath: ledger.path) ? " ✎" : " ∅"
    }

    func exists(_ window: WindowKey) async -> Bool { self.window(window) != nil }
    func frame(of window: WindowKey) async -> CGRect? { self.window(window)?.frame }

    func move(_ window: WindowKey, to frame: CGRect) async -> CGRect? {
        guard self.window(window) != nil else { return nil }
        journal.add("move \(window.id) \(frame.short)\(mark)")
        setFrame(window, frame)
        return frame
    }

    func isFullScreen(_ window: WindowKey) async -> Bool { self.window(window)?.fullScreen ?? false }

    func setFullScreen(_ window: WindowKey, _ on: Bool) async {
        journal.add("fullscreen \(window.id) \(on ? "on" : "off")")
        state.withLock { $0[window]?.fullScreen = on }
    }

    func focus(_ window: WindowKey) async { journal.add("focus \(window.id)") }

    func zoom(_ window: WindowKey, steps: Int) async -> Bool {
        guard self.window(window) != nil else { return false }
        journal.add("zoom \(window.id) \(steps > 0 ? "+" : "")\(steps)\(mark)")
        state.withLock { $0[window]?.zoom += steps }
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
