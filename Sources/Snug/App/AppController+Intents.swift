// AppController 的意图方法（界面、菜单、热键都走这里）和退出收尾
import AppKit
import ServiceManagement
import SnugCore

extension AppController: AppIntents {
    func setPaused(_ on: Bool) { changeConfig("暂停 Snug → \(on ? "开" : "关")") { $0.paused = on } }

    func setVirtualDisplayEnabled(_ on: Bool) {
        changeConfig("虚拟屏 → \(on ? "开" : "关")") { $0.virtualDisplayEnabled = on }
    }

    func setKeepOnlyVirtual(_ on: Bool) {
        changeConfig("远程时只保留虚拟屏 → \(on ? "开" : "关")") { $0.keepOnlyVirtual = on }
    }

    func setWatchdogEnabled(_ on: Bool) {
        guard changeConfig("看门狗 → \(on ? "开" : "关")", { $0.watchdogEnabled = on }) else { return }
        if let watchdog {
            watchdog.sync(enabled: on)
        } else {
            Log.info("不是以 .app 运行，看门狗不安装（可手动运行 --watchdog）")
        }
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            state.notice = nil
            Log.info("设置：开机启动 → \(on ? "开" : "关")")
        } catch {
            state.notice = "开机启动没设置成功：\(error.localizedDescription)。先把 Snug 放进「应用程序」文件夹再试。"
            Log.error("开机启动设置失败：\(error)")
        }
        refreshLaunchAtLogin()
    }

    func refreshLaunchAtLogin() {
        state.update(\.launchAtLogin, SMAppService.mainApp.status == .enabled)
    }

    func updateDevice(_ row: DeviceProfile) throws {
        do {
            try store.update { try $0.replaceDevice(row) }
        } catch let issue as DeviceSizeIssue {
            throw issue
        } catch {
            state.notice = "设备设置没能保存：\(error)"
            Log.error("保存设备「\(row.name)」失败：\(error)")
            throw error
        }
        Log.info("设置：设备「\(row.name)」→ \(row.kind == .computer ? "不指定分辨率" : row.hasSize ? row.sizeLabel : "未填写")")
        publishConfig()
    }

    func importDevices() {
        guard state.deviceImport != .reading else { return }
        guard UUAccessibility.isTrusted else {
            state.deviceImport = .failed("需要先授权，才能读到 UU远程 里的设备。")
            return
        }
        guard let pid = UURemoteApp.pid() else {
            state.deviceImport = .failed("UU远程 没有在运行。打开它再试。")
            return
        }
        state.deviceImport = .reading
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // 主窗口没开就先点开，等它画出来再读；都在后台，主线程不卡（修 B4）
            if !UUAccessibility.hasMainWindow(pid: pid) {
                UUAccessibility.showMainWindow(pid: pid)
                Thread.sleep(forTimeInterval: 1)
            }
            let found = UUAccessibility.readDevices(pid: pid)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.finishImport(found) }
            }
        }
    }

    private func finishImport(_ found: [UUDevice]?) {
        let others = (found ?? []).filter { !$0.isSelf }
        guard !others.isEmpty else {
            state.deviceImport = .failed("没读到设备列表。打开 UU远程 的「全部设备」页，再点「从 UU远程 导入」。")
            Log.warn("导入设备：没读到（\(found == nil ? "主窗口读不到" : "列表为空")）")
            return
        }
        do {
            try store.update { $0.devices = DeviceImport.merge(found: others, saved: $0.devices) }
        } catch {
            state.deviceImport = .failed("读到了 \(others.count) 台设备，但没能保存：\(error.localizedDescription)")
            Log.error("导入设备后保存失败：\(error)")
            return
        }
        state.deviceImport = .finished("已从 UU远程 导入 \(others.count) 台设备（不含这台 Mac）。")
        Log.info("导入设备：\(others.map(\.name))")
        publishConfig()
    }

    /// 热键 ⌃⌥⌘9 / 菜单：远程中按，本次远程不再熄屏；不在远程中按，只恢复这一下，不影响下一次远程（修 B11）
    func restoreScreensNow() {
        let inSession = session.suspendByUser()
        Log.info(inSession ? "手动恢复屏幕：本次远程不再熄灭物理屏" : "手动恢复屏幕（不在远程中，不影响下一次远程）")
        feature.userRequestedRestore(session: session)
        publishDisplay()
    }

    func restoreLayoutNow() {
        Log.info("手动还原屏幕布局")
        executor.restoreLayoutNow()
        publishDisplay()
    }

    func quitLegacyApp() {
        LegacyApp.quit()
    }

    func markTourShown() { changeConfig("看过导览") { $0.tourShown = true } }

    func quit() { onQuitRequested?() }

    // MARK: 退出收尾

    /// 停止监控，让执行器收尾（恢复物理屏、释放虚拟屏、还原布局）。
    /// 收尾完成且物理屏都恢复了，才停本次登录的看门狗（修 B5：旧版先停看门狗再收尾，收尾没完成就没人兜底）；
    /// timeout 内没收完就照样回调，看门狗留着兜底。超时用加进 .common 的 Timer，退出流程里的 run loop 模式下也会触发
    func finishForQuit(stopWatchdog: Bool, timeout: TimeInterval, completion: @escaping @MainActor () -> Void) {
        state.quitting = true
        stopMonitoring()
        Log.info("退出收尾开始（最多等 \(Int(timeout))s）")
        var done = false
        let finish: @MainActor (Bool) -> Void = { [weak self] clean in
            guard !done else { return }
            done = true
            guard let self else { return completion() }
            let physicalOff = executor.physicalOff
            if !clean {
                Log.warn("收尾 \(Int(timeout))s 内没完成，先退出；物理屏如果还关着，交给看门狗 / snug-rescue")
            } else if physicalOff {
                Log.warn("收尾完成，但物理屏还没恢复，看门狗留着兜底")
            }
            if stopWatchdog, clean, !physicalOff { watchdog?.stopForSession() }
            completion()
        }
        executor.shutdown { finish(true) }
        let timer = Timer(timeInterval: timeout, repeats: false) { _ in
            MainActor.assumeIsolated { finish(false) }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    // MARK: 配置

    /// 改配置、写盘、通知模块与界面。写盘失败时配置保持原样，界面上提示
    @discardableResult
    func changeConfig(_ what: String, _ change: (inout AppConfig) -> Void) -> Bool {
        do {
            try store.update(change)
        } catch {
            state.notice = "设置没能保存：\(error.localizedDescription)"
            Log.error("设置（\(what)）写盘失败：\(error)")
            publishConfig()
            return false
        }
        Log.info("设置：\(what)")
        publishConfig()
        return true
    }
}
