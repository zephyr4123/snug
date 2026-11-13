// 手机屏上列表里的窗口：列表露出来时每 1.5 秒刷新一次，收起就停；App 图标按 bundle ID 缓存
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
            while !Task.isCancelled {
                let list = await service.list()
                guard let self, !Task.isCancelled else { return }
                if list != windows { windows = list }
                loaded = true
                try? await Task.sleep(for: .seconds(Self.refreshInterval))
            }
        }
    }

    func stopRefreshing() {
        refreshing?.cancel()
        refreshing = nil
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
