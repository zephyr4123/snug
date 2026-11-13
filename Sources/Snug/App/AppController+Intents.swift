// AppController 的意图（设置窗口、菜单栏、手机屏上的列表都走这里）和退出收尾
import AppKit
import ServiceManagement
import SnugCore

extension AppController: AppIntents {
    func setPhoneScreen(_ on: Bool) { changeConfig("手机屏 → \(on ? "开" : "关")") { $0.phoneScreen = on } }

    func setGestures(_ on: Bool) {
        guard changeConfig("手机手势 → \(on ? "开" : "关")", { $0.gestures = on }) else { return }
        syncGestures()
    }

    func setZoomSteps(_ steps: Int) {
        let steps = min(max(steps, AppConfig.zoomStepsRange.lowerBound), AppConfig.zoomStepsRange.upperBound)
        guard changeConfig("放大字号 → \(steps) 级", { $0.zoomSteps = steps }) else { return }
        desk.defaultZoom = steps
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            state.notice = nil
            Log.info("设置：开机启动 → \(on ? "开" : "关")")
        } catch {
            state.notice = "开机启动设置失败：请将 Snug 移至「应用程序」后重试"
            Log.error("开机启动设置失败：\(error)")
        }
        refreshLaunchAtLogin()
    }

    func refreshLaunchAtLogin() {
        state.update(\.launchAtLogin, SMAppService.mainApp.status == .enabled)
    }

    func markWelcomed() { changeConfig("看过欢迎页") { $0.welcomed = true } }

    func quitLegacyApp() { LegacyApp.quit() }

    func quit() { onQuitRequested?() }

    // MARK: 退出收尾

    /// 停止监控，放回窗口、撤掉手机屏。timeout 内没收完也照样回调：手机屏会随进程退出消失，
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
            await desk.shutdown()
            finish(true)
        }
        let timer = Timer(timeInterval: timeout, repeats: false) { _ in
            MainActor.assumeIsolated { finish(false) }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    // MARK: 配置

    /// 改配置、写盘、通知界面。写盘失败时配置保持原样，界面上提示
    @discardableResult
    func changeConfig(_ what: String, _ change: (inout AppConfig) -> Void) -> Bool {
        do {
            try store.update(change)
        } catch {
            state.notice = "设置未能保存：\(error.localizedDescription)"
            Log.error("设置（\(what)）写盘失败：\(error)")
            return false
        }
        Log.info("设置：\(what)")
        state.update(\.config, store.config)
        return true
    }
}

extension AppController: PhoneIntents {
    func pull(_ window: WindowInfo) { desk.pull(window) }
    func showList() { desk.showList() }
    func returnToPlaced() { desk.returnToPlaced() }
    func putBack() { desk.putBack() }
    func rotate() { desk.rotate() }
    func zoom(by delta: Int) { desk.zoom(by: delta) }
}
