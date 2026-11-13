// 搬窗口、调字号：辅助功能接口 + 按 pid 投递的按键。
// 辅助功能的调用会阻塞（App 卡住时每次最多等 1 秒），全部放在自己的串行队列上做，主线程不等。
// 搬窗口时按「进程号 + 系统窗口编号」现找，不留辅助功能对象（App 重建窗口后旧对象会失效）；
// 只有列表留着别的空间里找出来的对象，因为找一遍太贵（见 remoteWindows(pid:now:)）。
// 不管窗口在哪块屏、哪个桌面空间、是否全屏或最小化都找得到（见 AX.allWindows）；
// 窗口在不在问窗口服务器（exists），不经过 App：App 卡住时辅助功能读不到，不能当成窗口关了
import AppKit
import ApplicationServices
import SnugCore

public final class WindowService: WindowControl {
    /// 每次重试之间等的时间、最多试几次：跨屏改大小时 App 会按它以为的那块屏夹紧尺寸，刚加的屏 App 也可能还没认到
    static let retryDelay: TimeInterval = 0.25
    static let maxTries = 10
    /// kVK_ANSI_Equal、kVK_ANSI_Minus（不为两个常量引入 Carbon：它的 WindowKey 会和我们的重名）
    static let equalKey: CGKeyCode = 0x18
    static let minusKey: CGKeyCode = 0x1B
    /// 别的桌面空间里的窗口隔这么久才整个重新试一遍（见 remoteWindows(pid:now:)）
    static let remoteRescanInterval: TimeInterval = 10

    private let queue = DispatchQueue(label: "com.zephyr4123.snug.windows", qos: .userInitiated)
    /// 每个 App 用远程令牌试出来的窗口对象和试的时刻（单调时钟）。只在 queue 上读写
    private let remote = Locked<[pid_t: (windows: [AXUIElement], scannedAt: TimeInterval)]>([:])

    public init() {}

    // MARK: WindowControl

    // 窗口服务器知道每个窗口（别的桌面空间、最小化、藏起来的也在），不用等 App 响应，也不要权限

    public func exists(_ window: WindowKey) async -> Bool { Self.serverInfo(window) != nil }

    public func isShown(_ window: WindowKey) async -> Bool {
        (Self.serverInfo(window)?[kCGWindowIsOnscreen as String] as? Bool) == true
    }

    public func look(_ window: WindowKey) async -> WindowLook? {
        await run {
            guard let element = AX.element(for: window), let frame = AX.frame(element) else { return nil }
            return WindowLook(frame: frame, fullScreen: AX.flag(element, AX.fullScreen), minimized: AX.flag(element, kAXMinimizedAttribute))
        }
    }

    public func move(_ window: WindowKey, to frame: CGRect) async -> CGRect? {
        await run {
            guard let element = AX.element(for: window) else { return nil }
            return Self.move(element, to: frame)
        }
    }

    public func setFullScreen(_ window: WindowKey, _ on: Bool) async {
        await run {
            guard let element = AX.element(for: window) else { return }
            AX.set(element, AX.fullScreen, on as CFBoolean)
            Self.wait(seconds: 5) { AX.flag(element, AX.fullScreen) == on }
            // 等全屏动画走完，不然紧接着的挪动会被动画盖掉
            Thread.sleep(forTimeInterval: 1.2)
        }
    }

    public func setMinimized(_ window: WindowKey, _ on: Bool) async {
        await run {
            guard let element = AX.element(for: window) else { return }
            Self.setMinimized(element, on)
        }
    }

    public func focus(_ window: WindowKey) async {
        await run {
            guard let element = AX.element(for: window) else { return }
            if AX.flag(element, kAXMinimizedAttribute) { Self.setMinimized(element, false) }
            AX.raise(element)
        }
        await MainActor.run {
            if NSRunningApplication(processIdentifier: window.pid)?.activate() == false {
                Log.warn("激活 pid \(window.pid) 没成功，键盘输入可能进不了这个窗口")
            }
        }
    }

    public func zoom(_ window: WindowKey, steps: Int) async -> Bool {
        await run {
            guard steps != 0 else { return true }
            guard let element = AX.element(for: window) else { return false }
            // 按键投给 App，App 交给它的当前窗口：先把这个窗口设成当前窗口
            AX.raise(element)
            let key = steps > 0 ? Self.equalKey : Self.minusKey
            for _ in 0..<abs(steps) {
                for down in [true, false] {
                    guard let event = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: down) else { continue }
                    event.flags = .maskCommand
                    event.postToPid(window.pid)
                }
                Thread.sleep(forTimeInterval: 0.08)
            }
            return true
        }
    }

    public func snapshot() async -> [WindowKey: CGRect] {
        let apps = await Self.regularApps()
        return await run {
            var frames: [WindowKey: CGRect] = [:]
            for app in apps {
                for element in AX.respondingWindows(pid: app.pid) ?? [] where AX.isStandard(element) && !AX.flag(element, kAXMinimizedAttribute) {
                    guard let id = AX.windowID(element), let frame = AX.frame(element) else { continue }
                    frames[WindowKey(pid: app.pid, id: id)] = frame
                }
            }
            return frames
        }
    }

    public func restore(_ snapshot: [WindowKey: CGRect], except: WindowKey?) async {
        await run {
            for (window, saved) in snapshot where window != except {
                guard let element = AX.element(for: window), let now = AX.frame(element), !now.matches(saved) else { continue }
                let got = Self.move(element, to: saved)
                Log.info("系统挪了 pid \(window.pid) 的窗口 \(now.short)，已放回 \(saved.short)"
                         + (got.map { $0.matches(saved) } == true ? "" : "（没对上，现在 \(got?.short ?? "?")）"))
            }
        }
    }

    // MARK: 窗口列表（手机屏上的卡片）

    /// 所有可以放上手机屏的窗口：不管在哪块屏、哪个桌面空间，全屏、最小化的也算。最近用过的在前
    public func list() async -> [WindowInfo] {
        let apps = await Self.regularApps()
        return await run {
            let now = ProcessInfo.processInfo.systemUptime
            let running = Set(apps.map(\.pid))
            self.remote.withLock { $0 = $0.filter { running.contains($0.key) } }
            var windows: [WindowInfo] = []
            for app in apps {
                let all = AX.allWindows(pid: app.pid) { self.remoteWindows(pid: app.pid, now: now) }
                for element in all where AX.isStandard(element) {
                    guard let id = AX.windowID(element) else { continue }
                    windows.append(WindowInfo(key: WindowKey(pid: app.pid, id: id), app: app.name, bundleID: app.bundleID,
                                              title: WindowInfo.visibleTitle(AX.string(element, kAXTitleAttribute) ?? "")))
                }
            }
            return WindowList.ordered(windows, frontToBack: Self.frontToBack())
        }
    }

    // MARK: 内部

    /// 别的桌面空间里的窗口：试一遍是一千次跨进程调用（实测十个 App 约 240ms），列表每 1.5 秒刷一次时不能每次都试。
    /// 试出来的对象记下来接着用（关掉的窗口读不到属性，自然掉出列表）。过了 remoteRescanInterval 先照旧用，
    /// 排在这次列表后面再整个试一遍，找出这期间新开、又去了别的空间的窗口：列表一露出来就要快，不等这一遍
    /// 试到一半 App 卡住时结果不全：不记、不覆盖旧的，不然它在别的空间里的窗口要从列表里消失一阵
    private func remoteWindows(pid: pid_t, now: TimeInterval) -> [AXUIElement] {
        guard let cached = remote.withLock({ $0[pid] }) else {
            let scan = AX.remoteWindows(pid: pid)
            if scan.complete { remote.withLock { $0[pid] = (scan.windows, now) } }
            return scan.windows
        }
        if now - cached.scannedAt >= Self.remoteRescanInterval {
            remote.withLock { $0[pid]?.scannedAt = now }
            queue.async { [remote] in
                let scan = AX.remoteWindows(pid: pid)
                if scan.complete { remote.withLock { $0[pid]?.windows = scan.windows } }
            }
        }
        return cached.windows
    }

    /// 窗口服务器里这个窗口的信息；没有、或编号已经归了别的进程返回 nil
    private static func serverInfo(_ window: WindowKey) -> [String: Any]? {
        guard let info = (CGWindowListCopyWindowInfo([.optionIncludingWindow], window.id) as? [[String: Any]])?.first,
              (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == window.pid else { return nil }
        return info
    }

    /// 等到条件成立，最多等 seconds 秒。App 卡住时每次读都要等满超时，所以按截止时间算，不按次数
    private static func wait(seconds: TimeInterval, until done: () -> Bool) {
        let deadline = ProcessInfo.processInfo.systemUptime + seconds
        while !done(), ProcessInfo.processInfo.systemUptime < deadline { Thread.sleep(forTimeInterval: 0.25) }
    }

    private func run<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work()) }
        }
    }

    /// 设好后等它真的变过去，再等动画走完
    private static func setMinimized(_ element: AXUIElement, _ on: Bool) {
        AX.set(element, kAXMinimizedAttribute, on as CFBoolean)
        wait(seconds: 3) { AX.flag(element, kAXMinimizedAttribute) == on }
        Thread.sleep(forTimeInterval: 0.5)
    }

    /// 先改大小、再挪、再改大小，然后核对，对不上就重来。
    /// 位置对了、连着两次尺寸都一样，就是 App 限定了最小尺寸（系统设置、Safari……），再试也一样，不空等
    private static func move(_ element: AXUIElement, to target: CGRect) -> CGRect? {
        var got: CGRect?
        for _ in 0..<maxTries {
            AX.setSize(element, target.size)
            AX.setPosition(element, target.origin)
            AX.setSize(element, target.size)
            Thread.sleep(forTimeInterval: retryDelay)
            let previous = got
            got = AX.frame(element)
            guard let now = got, !now.matches(target) else { break }
            let placed = abs(now.minX - target.minX) < 2 && abs(now.minY - target.minY) < 2
            if let previous, now.matches(previous), placed { break }
        }
        return got
    }

    private struct App: Sendable {
        let pid: pid_t
        let name: String
        let bundleID: String?
    }

    /// 普通 App（有 Dock 图标的），不含 Snug 自己
    private static func regularApps() async -> [App] {
        await MainActor.run {
            NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular && $0 != NSRunningApplication.current }
                .map { App(pid: $0.processIdentifier, name: $0.localizedName ?? "未命名", bundleID: $0.bundleIdentifier) }
        }
    }

    /// 屏上窗口从前到后的编号
    private static func frontToBack() -> [UInt32] {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        return (list ?? []).compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value }
    }
}
