// AppController 的意图（设置窗口、菜单栏、各块屏上的面板都走这里）和退出收尾
import AppKit
import ServiceManagement
import SnugCore

extension AppController: AppIntents {
    // MARK: 屏幕列表

    func setScreenEnabled(_ id: ScreenID, _ on: Bool) {
        editScreen(id, "开关 → \(on ? "开" : "关")") { $0.enabled = on }
    }

    /// name 是表单里原样填的；没填（只打了空格也算）就交给 AppConfig.addScreen 按型号和方向起名
    func addScreen(orientation: Orientation, device: DeviceChoice, name: String) {
        let name = name.trimmingCharacters(in: .whitespaces)
        var added: ScreenConfig?
        // 最后起成什么名字记在下面「新屏」那一行
        guard changeConfig("加屏：\(orientation.title) · \(device.title)", {
            added = $0.addScreen(orientation: orientation, device: device, name: name.isEmpty ? nil : name)
        }), let added else {
            // 满了 AppConfig 不加（配置没变）；写盘失败 changeConfig 已经记过
            if added == nil { Log.warn("屏幕列表已有 \(ScreenConfig.limit) 块，不再加") }
            return
        }
        Log.info("新屏「\(added.name)」\(ScreenPlan.fit(of: added))，序列号 \(added.serials.map(String.init).joined(separator: "/"))")
        applyPlan()
    }

    func removeScreen(_ id: ScreenID) {
        guard let screen = state.screen(id), changeConfig("删屏「\(screen.name)」", { $0.removeScreen(id) }) else { return }
        applyPlan()
    }

    func setScreenDevice(_ id: ScreenID, _ device: DeviceChoice) {
        let fit = ScreenPlan.fit(device, state.screen(id)?.orientation ?? .portrait)
        let reset = state.screen(id)?.baseWidth == nil ? "" : "，分辨率回到默认"
        editScreen(id, "型号 → \(device.title)（\(fit)）\(reset)") { $0.setDevice(device) }
    }

    func setScreenResolution(_ id: ScreenID, _ width: Int?) {
        guard let screen = state.screen(id) else { return }
        let fit = ScreenPlan.fit(screen.device, screen.orientation, width: width)
        editScreen(id, "分辨率 → \(width.map { "\($0) 点宽" } ?? "默认")（\(fit)）") { $0.baseWidth = width }
    }

    /// 改名下次建屏时生效：正在用的屏中途改名要撤了重建，远控里也得重选屏
    func renameScreen(_ id: ScreenID, _ name: String) {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        editScreen(id, "名字 → \(name)") { $0.name = name }
    }

    func setKeepScreensReady(_ on: Bool) {
        guard changeConfig("提前准备虚拟屏 → \(on ? "开" : "关")", { $0.keepScreensReady = on }) else { return }
        applyPlan()
    }

    func setMainScreen(_ id: ScreenID?) {
        let name = id.flatMap { state.screen($0)?.name }
        guard changeConfig("设为主屏 → \(name.map { "「\($0)」" } ?? "不改")", { $0.mainScreen = id }) else { return }
        applyPlan()
    }

    /// 改屏幕列表里的一项，马上按新配置算一遍要哪些屏
    private func editScreen(_ id: ScreenID, _ what: String, _ change: (inout ScreenConfig) -> Void) {
        guard let screen = state.screen(id) else { return }
        guard changeConfig("「\(screen.name)」的\(what)", { config in
            if let i = config.screens.firstIndex(where: { $0.id == id }) { change(&config.screens[i]) }
        }) else { return }
        applyPlan()
    }

    // MARK: 触控

    func setGestures(_ on: Bool) {
        guard changeConfig("手势 → \(on ? "开" : "关")", { $0.gestures = on }) else { return }
        syncGestures()
    }

    /// 关掉时把浮着的截图一并收掉
    func setScreenshot(_ on: Bool) {
        guard changeConfig("截图键 → \(on ? "开" : "关")", { $0.screenshot = on }) else { return }
        if on { refreshScreenRecording() } else { screenshots.dismiss() }
    }

    func setZoomSteps(_ steps: Int) {
        let steps = steps.clamped(to: AppConfig.zoomStepsRange)
        guard changeConfig("放大字号 → \(steps) 级", { $0.zoomSteps = steps }) else { return }
        desks.setDefaultZoom(steps)
    }

    /// 打开没成时写明原因：在「登录项」里被关过（系统要用户去那里允许）、不在「应用程序」里，还是别的
    func setLaunchAtLogin(_ on: Bool) {
        var failed = false
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            Log.info("设置：开机启动 → \(on ? "开" : "关")")
        } catch {
            failed = true
            Log.error("开机启动设置失败（\(Bundle.main.bundlePath)）：\(error)")
        }
        let status = SMAppService.mainApp.status
        let issue: LoginItemIssue? = if on, status == .requiresApproval {
            .needsApproval
        } else if failed {
            Bundle.main.bundlePath.hasPrefix("/Applications/") ? .failed : .notInApplications
        } else {
            nil
        }
        if issue == .needsApproval { Log.warn("开机启动待用户在「登录项」里允许") }
        state.update(\.loginItemIssue, issue)
        refreshLaunchAtLogin()
    }

    func openLoginItemsSettings() { SMAppService.openSystemSettingsLoginItems() }

    /// 装了哪些只在启动时认屏的远控：启动时、Snug 被激活（打开设置）时重查，装上、删掉不用重启 Snug
    func refreshRemoteInstalls() {
        let installed = Remotes.all.map(\.identity).filter { remote in
            remote.seesScreensOnlyAtLaunch && remote.bundleIDs.contains { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }
        }
        state.update(\.launchOnlyRemotes, installed.map(\.displayName))
    }

    func refreshLaunchAtLogin() {
        let enabled = SMAppService.mainApp.status == .enabled
        state.update(\.launchAtLogin, enabled)
        if enabled { state.update(\.loginItemIssue, nil) }
    }

    func markWelcomed() { changeConfig("看过欢迎页") { $0.welcomed = true } }

    /// 记下这次运行的版本，交回是不是刚换了版本（应用内更新或手动替换）。第一次记的不算
    func recordVersion() -> Bool {
        guard let current = Updater.current, state.config.lastVersion != current else { return false }
        let previous = state.config.lastVersion
        changeConfig("运行版本 → \(current)") { $0.lastVersion = current }
        return previous != nil
    }

    func quitLegacyApp() { LegacyApp.quit() }

    func quit() { onQuitRequested?() }

    func checkForUpdates() { updater.check(userInitiated: true) }

    func installUpdate() { updater.install() }

    /// 换了更新源，上一个源连不上之类的提示就不作数了
    func setUpdateSource(_ source: UpdateSource) {
        guard changeConfig("更新源 → \(source.title)", { $0.updateSource = source }) else { return }
        state.update.problem = nil
    }

    func openDownloadPage() { NSWorkspace.shared.open(state.config.updateSource.downloadPage) }

    // MARK: 退出收尾

    /// 停止监控，放回窗口、撤掉所有屏。timeout 内没收完也照样回调：屏会随进程退出消失，
    /// 窗口位置和字号留给下次启动按还原记录处理。超时用加进 .common 的 Timer，退出流程的 run loop 模式下也会触发
    func finishForQuit(timeout: TimeInterval, completion: @escaping @MainActor () -> Void) {
        state.quitting = true
        stopMonitoring()
        Log.info("退出收尾开始（最多等 \(Int(timeout))s）")
        var done = false
        let finish: @MainActor (Bool) -> Void = { clean in
            guard !done else { return }
            done = true
            if !clean { Log.warn("收尾 \(Int(timeout))s 内没做完，先退出；窗口留给下次启动放回") }
            completion()
        }
        Task { @MainActor in
            await desks.shutdown()
            finish(true)
        }
        let timer = Timer(timeInterval: timeout, repeats: false) { _ in
            MainActor.assumeIsolated { finish(false) }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    // MARK: 配置

    /// 改配置、写盘、通知界面，交回是不是真的改了（值没变就什么都不做，也不打日志）。写盘失败时配置保持原样，界面上提示
    @discardableResult
    func changeConfig(_ what: String, _ change: (inout AppConfig) -> Void) -> Bool {
        do {
            guard try store.update(change) else { return false }
        } catch {
            state.update(\.configSaveFailed, true)
            Log.error("设置（\(what)）写盘失败：\(error)")
            return false
        }
        Log.info("设置：\(what)")
        state.update(\.configSaveFailed, false)
        state.update(\.config, store.config)
        return true
    }
}

/// 一块屏上的面板发起的意图：带上是哪块屏，交给 AppController
@MainActor
final class ScreenIntents: TouchIntents {
    let id: ScreenID
    private unowned let app: AppController
    private var desks: DeskSet { app.desks }

    init(id: ScreenID, app: AppController) {
        self.id = id
        self.app = app
    }

    func pull(_ window: WindowInfo) { desks.pull(window, on: id) }

    func open(_ app: AppInfo) {
        switch AppList.action(for: app, running: self.app.catalog.running) {
        case .pull(let window): desks.pull(window, on: id)
        case .open(let app): desks.open(app, on: id)
        }
    }

    func newWindow(_ app: RunningApp) { desks.newWindow(app, on: id) }
    func quit(_ app: RunningApp) { desks.quit(app, from: id) }
    func forceQuit(pid: Int32, app: String) { desks.forceQuit(pid: pid, app: app, from: id) }
    func close(_ window: WindowInfo) { desks.close(window, from: id) }
    func dismissNotice() { desks.dismissNotice(on: id) }
    func showList() { desks.showList(on: id) }
    func returnToPlaced() { desks.returnToPlaced(on: id) }
    func putBack() { desks.putBack(on: id) }
    func zoom(by delta: Int) { desks.zoom(by: delta, on: id) }
    func setDevice(_ device: DeviceChoice) { app.setScreenDevice(id, device) }
    func setResolution(_ width: Int?) { app.setScreenResolution(id, width) }
    func dismissScreen() { desks.dismissScreen(id) }
    func cancelMain() { app.setMainScreen(nil) }

    func takeScreenshot() {
        guard let window = app.state.desks.desks[id]?.placed?.window else { return }
        Task { await app.screenshots.take(window, on: id) }
    }

    func openCrop() { app.screenshots.openCrop() }
    func cancelCrop() { app.screenshots.cancelCrop() }
    func finishCrop(_ selection: CGRect) { app.screenshots.finishCrop(selection) }
}

/// 一块电脑屏的资源库的意图：落到这块屏上
final class ComputerScreenIntents: ComputerIntents {
    let id: ScreenID
    private unowned let app: AppController
    private var desks: DeskSet { app.desks }

    init(id: ScreenID, app: AppController) {
        self.id = id
        self.app = app
    }

    func focus(_ window: WindowInfo) { desks.focus(window, on: id) }
    func pull(_ window: WindowInfo) { desks.pull(window, on: id) }
    func open(_ app: AppInfo) { desks.open(app, on: id) }
    func putBack(_ window: WindowKey) { desks.putBack(window, on: id) }
    func dismissNotice() { desks.dismissNotice(on: id) }
}
