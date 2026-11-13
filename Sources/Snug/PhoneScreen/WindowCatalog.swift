// 手机屏上列表里的窗口：列表露出来时每 1.5 秒刷新一次，收起就停；App 图标按 bundle ID 缓存。
// 每次露出来，第一次刷新按「最近用过的在前」重排，之后只增删、不换位置（见 WindowList.keepingOrder）。
// 正在放窗口时暂停（列表被盖住，刷了也看不见，还和搬窗口排同一条队）；一次远程结束就清空，下次从头读
import AppKit
import Observation
import SnugCore
import SnugSystem

@MainActor
@Observable
final class WindowCatalog {
    static let refreshInterval: TimeInterval = 1.5

    private(set) var windows: [WindowInfo]
    /// 第一次刷新完成前不显示「没有窗口」
    private(set) var loaded: Bool

    @ObservationIgnored private let service: WindowService?
    @ObservationIgnored private var refreshing: Task<Void, Never>?
    @ObservationIgnored private var paused = false
    @ObservationIgnored private var icons: [String: NSImage] = [:]

    init(service: WindowService) {
        self.service = service
        windows = []
        loaded = false
    }

    /// 渲染样例用：固定的窗口，不刷新
    init(sample: [WindowInfo], loaded: Bool = true) {
        service = nil
        windows = sample
        self.loaded = loaded
    }

    func startRefreshing() {
        guard refreshing == nil, let service else { return }
        refreshing = Task { [weak self] in
            var reorder = true
            while !Task.isCancelled {
                if self?.paused == true {
                    try? await Task.sleep(for: .seconds(Self.refreshInterval))
                    continue
                }
                let list = await service.list()
                guard let self, !Task.isCancelled else { return }
                let next = reorder ? list : WindowList.keepingOrder(of: windows, updatedWith: list)
                if next != windows { windows = next }
                loaded = true
                reorder = false
                try? await Task.sleep(for: .seconds(Self.refreshInterval))
            }
        }
    }

    func stopRefreshing() {
        refreshing?.cancel()
        refreshing = nil
    }

    /// 暂停、继续刷新：不重开，继续后也不重排
    func setPaused(_ on: Bool) { paused = on }

    /// 一次远程结束：停下、清空，下次露出时显示「正在读取窗口」，不拿上次的旧列表
    func reset() {
        stopRefreshing()
        windows = []
        loaded = false
    }

    func icon(for window: WindowInfo) -> NSImage {
        let key = window.bundleID ?? "pid:\(window.key.pid)"
        if let cached = icons[key] { return cached }
        let icon = window.bundleID.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
            ?? NSRunningApplication(processIdentifier: window.key.pid)?.icon
            ?? NSWorkspace.shared.icon(for: .application)
        icons[key] = icon
        return icon
    }
}
