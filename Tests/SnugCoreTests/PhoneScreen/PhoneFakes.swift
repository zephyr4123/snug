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
    /// 假屏的左上角（辅助功能坐标）和菜单栏高度：可放区域 = 这一档扣掉菜单栏和底部小横条
    nonisolated static let origin = CGPoint(x: 2000, y: 0)
    nonisolated static let menuBar: CGFloat = 25

    let journal: Journal
    var nextID: DisplayID = 100
    /// 接下来这么多次建屏失败
    var failuresLeft = 0
    /// 换档不成（帮手进程失败）：屏还是原来那一档
    var switchFails = false
    /// 读不到可放区域（屏幕组合还在变）
    var areaUnavailable = false
    /// 加屏、撤屏时 macOS 的副作用（把窗口拉过去、挪走）
    var onCreate: (() -> Void)?
    var onRetire: (() -> Void)?
    /// 记下建屏、撤屏的时刻（检查「建好不到 2.5 秒不撤」）
    var clock: (() -> TimeInterval)?
    private(set) var createdAt: [DisplayID: TimeInterval] = [:]
    private(set) var retiredAt: [DisplayID: TimeInterval] = [:]
    /// 每块屏此刻是哪一档；建好时是基准宽度。设成别的值模拟系统自己改了模式
    var widths: [DisplayID: Int] = [:]

    init(journal: Journal) { self.journal = journal }

    /// 这一档的可放区域，和真的一样：整屏扣掉菜单栏和（跟着缩放的）底部小横条
    nonisolated static func area(width: Int) -> CGRect {
        let size = ScreenFit.size(width: width)
        let bar = ScreenFit.homeBarHeight(screenWidth: size.width)
        return CGRect(x: origin.x, y: origin.y + menuBar, width: size.width, height: size.height - menuBar - bar)
    }

    func create() async throws -> DisplayID {
        journal.add("create")
        if failuresLeft > 0 {
            failuresLeft -= 1
            throw PhoneScreenError.neverOnline
        }
        nextID += 1
        createdAt[nextID] = clock?()
        widths[nextID] = ScreenFit.baseWidth
        onCreate?()
        return nextID
    }

    func retire(_ id: DisplayID) async {
        journal.add("retire \(id)")
        retiredAt[id] = clock?()
        widths[id] = nil
        onRetire?()
    }

    func width(_ id: DisplayID) -> Int? { widths[id] }

    func setWidth(_ id: DisplayID, _ width: Int) async {
        journal.add("width \(id) \(width)")
        if !switchFails { widths[id] = width }
    }

    func bounds(_ id: DisplayID) -> CGRect? {
        widths[id].map { CGRect(origin: Self.origin, size: ScreenFit.size(width: $0)) }
    }

    func windowArea(_ id: DisplayID) -> CGRect? {
        guard !areaUnavailable, let width = widths[id] else { return nil }
        return Self.area(width: width)
    }
}

/// 假窗口：记住每个窗口的位置、是否全屏、是否最小化、字号级数
final class FakeWindows: WindowControl {
    struct Window: Sendable {
        var frame: CGRect
        var fullScreen = false
        /// 切全屏时换过去的另一个样子：全屏时是平时的位置，平时是整屏大小（和真的一样，全屏时读到的是整屏）
        var otherFrame: CGRect?
        var minimized = false
        /// App 把窗口藏起来了（被隐藏、关成了隐藏）：还在，但不在屏上
        var hidden = false
        var zoom = 0
    }

    let journal: Journal
    private let state = Locked<[WindowKey: Window]>([:])
    private let blocked = Locked(false)
    private let movesBlocked = Locked(false)
    private let zoomBlocked = Locked(false)
    private let grows = Locked(false)
    private let minSizes = Locked<[WindowKey: CGSize]>([:])
    private let moveHook = Locked<(@Sendable (WindowKey) -> Void)?>(nil)
    /// 设了就在每次挪窗口、发按键时记一下此刻还原记录在不在（检查「先记账再动手」）
    let ledger: URL?

    init(journal: Journal, ledger: URL? = nil) {
        self.journal = journal
        self.ledger = ledger
    }

    /// App 没响应（或辅助功能权限被收回）：窗口还在，但读不到、挪不动、发不了按键；传 false 恢复
    func block(_ on: Bool = true) { blocked.withLock { $0 = on } }
    /// 只是挪不动（App 卡在改窗口大小上），别的照常；传 false 恢复
    func blockMoves(_ on: Bool = true) { movesBlocked.withLock { $0 = on } }
    /// 只是字号按键发不出去（找窗口那一下刚好超时），别的照常；传 false 恢复
    func blockZoom(_ on: Bool = true) { zoomBlocked.withLock { $0 = on } }
    /// 像终端那样：调字号时保持行列数，窗口跟着变大
    func growOnZoom() { grows.withLock { $0 = true } }
    /// 像系统设置、Safari 那样：App 限定了最小尺寸，再小也压不下去
    func setMinSize(_ key: WindowKey, width: CGFloat = 0, height: CGFloat = 0) {
        minSizes.withLock { $0[key] = CGSize(width: width, height: height) }
    }
    /// 每次挪窗口前先调一下（检查挪的那一刻还原记录里写的是什么）
    func onMove(_ hook: @escaping @Sendable (WindowKey) -> Void) { moveHook.withLock { $0 = hook } }

    private var reachable: Bool { !blocked.withLock { $0 } }

    /// windowed：全屏窗口退出全屏后的平时位置
    func add(_ key: WindowKey, frame: CGRect, fullScreen: Bool = false, windowed: CGRect? = nil, minimized: Bool = false) {
        state.withLock { $0[key] = Window(frame: frame, fullScreen: fullScreen, otherFrame: windowed, minimized: minimized) }
    }

    func close(_ key: WindowKey) { _ = state.withLock { $0.removeValue(forKey: key) } }
    /// 像飞书、微信点关闭那样：窗口藏起来，还在
    func hide(_ key: WindowKey) { state.withLock { $0[key]?.hidden = true } }
    func window(_ key: WindowKey) -> Window? { state.withLock { $0[key] } }
    func setFrame(_ key: WindowKey, _ frame: CGRect) { state.withLock { $0[key]?.frame = frame } }

    private var mark: String {
        guard let ledger else { return "" }
        return FileManager.default.fileExists(atPath: ledger.path) ? " ✎" : " ∅"
    }

    func exists(_ window: WindowKey) async -> Bool { self.window(window) != nil }

    func isShown(_ window: WindowKey) async -> Bool {
        guard let w = self.window(window) else { return false }
        return !w.minimized && !w.hidden
    }

    func look(_ window: WindowKey) async -> WindowLook? {
        guard reachable, let w = self.window(window) else { return nil }
        return WindowLook(frame: w.frame, fullScreen: w.fullScreen, minimized: w.minimized)
    }

    func move(_ window: WindowKey, to frame: CGRect) async -> CGRect? {
        guard reachable, !movesBlocked.withLock({ $0 }), self.window(window) != nil else { return nil }
        moveHook.withLock { $0 }?(window)
        journal.add("move \(window.id) \(frame.short)\(mark)")
        var got = frame
        if let min = minSizes.withLock({ $0[window] }) {
            got.size = CGSize(width: max(got.width, min.width), height: max(got.height, min.height))
        }
        setFrame(window, got)
        return got
    }

    /// 切全屏：和另一个样子对换（退出全屏变回平时的位置，进全屏变回整屏）
    func setFullScreen(_ window: WindowKey, _ on: Bool) async {
        guard reachable else { return }
        journal.add("fullscreen \(window.id) \(on ? "on" : "off")\(mark)")
        state.withLock {
            guard var w = $0[window], w.fullScreen != on else { return }
            (w.frame, w.otherFrame) = (w.otherFrame ?? w.frame, w.frame)
            w.fullScreen = on
            $0[window] = w
        }
    }

    func setMinimized(_ window: WindowKey, _ on: Bool) async {
        guard reachable else { return }
        journal.add("minimize \(window.id) \(on ? "on" : "off")\(mark)")
        state.withLock { $0[window]?.minimized = on }
    }

    func focus(_ window: WindowKey) async { journal.add("focus \(window.id)") }

    func zoom(_ window: WindowKey, steps: Int) async -> Bool {
        guard reachable, !zoomBlocked.withLock({ $0 }), self.window(window) != nil else { return false }
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
