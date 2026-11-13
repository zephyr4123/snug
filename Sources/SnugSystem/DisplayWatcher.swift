// 屏幕配置变化（插拔外接屏、改模式、加撤手机屏）。每次变化系统会按块回调好几次，调用方自己去抖
import CoreGraphics
import Foundation

@MainActor
public final class DisplayWatcher {
    private let onChange: @MainActor () -> Void
    private var registered = false

    public init(onChange: @escaping @MainActor () -> Void) { self.onChange = onChange }

    public func start() {
        guard !registered else { return }
        registered = CGDisplayRegisterReconfigurationCallback(Self.callback, Unmanaged.passUnretained(self).toOpaque()) == .success
    }

    public func stop() {
        guard registered else { return }
        CGDisplayRemoveReconfigurationCallback(Self.callback, Unmanaged.passUnretained(self).toOpaque())
        registered = false
    }

    private static let callback: CGDisplayReconfigurationCallBack = { _, flags, info in
        // 「开始配置」那一下系统还没改完，等后面的回调
        guard !flags.contains(.beginConfigurationFlag), let info else { return }
        let watcher = Unmanaged<DisplayWatcher>.fromOpaque(info).takeUnretainedValue()
        DispatchQueue.main.async { MainActor.assumeIsolated { watcher.onChange() } }
    }
}
