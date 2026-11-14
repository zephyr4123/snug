// 手机屏的建、撤、换档（CGVirtualDisplay 私有接口）。实测过的做法（见记忆 project-phone-screen）：
// - 建屏时把 ScreenFit 的每一档都登记成模式，hiDPI 打开，maxPixels 正好是最宽一档的 2 倍：每一档都有 2 倍模式
// - 系统上线时用它记着的那一档（第一次是最宽的），所以上线后切回基准宽度
// - 换档交给帮手进程（主程序亲自切会让释放拖 40 秒以上）
// - 建好不上线就换备用身份
// - 在主线程建和释放；释放时不能留局部强引用，否则不会真正释放
import AppKit
import CGVirtualDisplayBridge
import SnugCore

@MainActor
public final class PhoneDisplayService: PhoneDisplays {
    static let onlineTimeout: TimeInterval = 6
    static let offlineTimeout: TimeInterval = 10
    /// 帮手切模式最多等这么久（正常不到一秒）
    nonisolated static let helperTimeout: TimeInterval = 10
    /// 切完等界面（NSScreen）认到新尺寸最多这么久：可放区域按它算，认到之前算出来的还是旧尺寸
    static let screenUpdateTimeout: TimeInterval = 2

    private var displays: [DisplayID: CGVirtualDisplay] = [:]
    /// 帮手进程：就是 Snug 自己，带 --set-mode 运行
    private let helper: URL

    public init(helper: URL) { self.helper = helper }

    public func create() async throws -> DisplayID {
        var madeAny = false
        for serial in PhoneScreenSpec.serials {
            guard let display = make(serial: serial) else {
                Log.warn("手机屏（serial=\(serial)）建不出来，换备用身份")
                continue
            }
            madeAny = true
            let id = display.displayID
            displays[id] = display
            guard await wait(id, online: true, timeout: Self.onlineTimeout) else {
                Log.warn("手机屏 #\(id)（serial=\(serial)）建好 \(Int(Self.onlineTimeout)) 秒没上线，换备用身份")
                await retire(id)
                continue
            }
            // 刚上线时模式还在变，等它定下来再看是哪一档
            try? await Task.sleep(for: .seconds(0.8))
            if width(id) != ScreenFit.baseWidth { await setWidth(id, ScreenFit.baseWidth) }
            return id
        }
        throw madeAny ? PhoneScreenError.neverOnline : PhoneScreenError.createFailed
    }

    public func retire(_ id: DisplayID) async {
        guard displays[id] != nil else {
            Log.warn("要撤的手机屏 #\(id) 不是本进程建的")
            return
        }
        autoreleasepool { displays[id] = nil }
        if await !wait(id, online: false, timeout: Self.offlineTimeout) {
            Log.warn("手机屏 #\(id) 释放 \(Int(Self.offlineTimeout)) 秒后仍在线")
        }
        // 系统挪窗口要一点时间，等它挪完再给窗口拍对比
        try? await Task.sleep(for: .seconds(1))
    }

    public func width(_ id: DisplayID) -> Int? {
        DisplayMode.hiDPIWidth(id)
    }

    public func setWidth(_ id: DisplayID, _ width: Int) async {
        let from = DisplayMode.describe(id)
        let status = await runHelper(id, width: width)
        guard status == 0 else {
            Log.warn("手机屏 #\(id) 换不到 \(width) 宽（帮手退出码 \(status.map(String.init) ?? "启动失败")），现在 \(DisplayMode.describe(id))")
            return
        }
        let switched = { self.width(id) == width && Screens.screen(for: id)?.frame.width == CGFloat(width) }
        let deadline = ProcessInfo.processInfo.systemUptime + Self.screenUpdateTimeout
        while !switched(), ProcessInfo.processInfo.systemUptime < deadline {
            try? await Task.sleep(for: .seconds(0.05))
        }
        if switched() {
            Log.info("手机屏 #\(id) 换到 \(width) 宽（原来 \(from)）")
        } else {
            Log.warn("手机屏 #\(id) 帮手说换到了 \(width) 宽，\(Int(Self.screenUpdateTimeout)) 秒内界面没认到，现在 \(DisplayMode.describe(id))")
        }
    }

    public func bounds(_ id: DisplayID) -> CGRect? {
        // CGDisplayBounds 和辅助功能用的是同一套全局坐标（左上原点）；屏不在时是空框
        let rect = CGDisplayBounds(id)
        return rect.isEmpty ? nil : rect
    }

    public func windowArea(_ id: DisplayID) -> CGRect? {
        guard let screen = Screens.screen(for: id) else { return nil }
        var area = Screens.axRect(fromAppKit: screen.visibleFrame)
        area.size.height -= ScreenFit.homeBarHeight(screenWidth: screen.frame.width)
        return area
    }

    // MARK: 内部

    private func make(serial: UInt32) -> CGVirtualDisplay? {
        let descriptor = CGVirtualDisplayDescriptor()
        descriptor.name = PhoneScreenSpec.name
        descriptor.maxPixelsWide = UInt32(ScreenFit.maxPixels.width)
        descriptor.maxPixelsHigh = UInt32(ScreenFit.maxPixels.height)
        descriptor.sizeInMillimeters = CGSize(width: PhoneScreenSpec.millimeters.width, height: PhoneScreenSpec.millimeters.height)
        descriptor.vendorID = PhoneScreenSpec.vendorID
        descriptor.productID = PhoneScreenSpec.productID
        descriptor.serialNum = serial
        guard let display = autoreleasepool(invoking: { CGVirtualDisplay(descriptor: descriptor) }) else { return nil }
        let settings = CGVirtualDisplaySettings()
        settings.hiDPI = true
        settings.modes = ScreenFit.widths.map { width in
            let size = ScreenFit.size(width: width)
            return CGVirtualDisplayMode(width: UInt(size.width), height: UInt(size.height), refreshRate: 60)
        }
        guard autoreleasepool(invoking: { display.apply(settings) }) else {
            Log.warn("手机屏（serial=\(serial)）apply 失败")
            return nil
        }
        return display
    }

    private func wait(_ id: DisplayID, online: Bool, timeout: TimeInterval) async -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while Self.isOnline(id) != online {
            guard ProcessInfo.processInfo.systemUptime < deadline else { return false }
            try? await Task.sleep(for: .seconds(0.25))
        }
        return true
    }

    private static func isOnline(_ id: DisplayID) -> Bool {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return false }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return false }
        return ids.prefix(Int(count)).contains(id)
    }

    /// 起帮手进程换档，等它退出；返回退出码，起不来返回 nil。
    /// 最多等 helperTimeout：帮手卡在屏幕配置里不退出，就结束它（换档本来就是尽力而为），不能让建屏和整条调度队一直等
    private func runHelper(_ id: DisplayID, width: Int) async -> Int32? {
        let process = Process()
        process.executableURL = helper
        process.arguments = ["--set-mode", "\(id)", "\(width)"]
        return await withCheckedContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                Log.error("帮手进程起不来（\(helper.path)）：\(error)")
                continuation.resume(returning: nil)
                return
            }
            // 只有 terminationHandler 会 resume：结束进程后它照样回调
            DispatchQueue.global().asyncAfter(deadline: .now() + Self.helperTimeout) {
                guard process.isRunning else { return }
                Log.error("帮手进程 \(Int(Self.helperTimeout))s 没退出（屏 #\(id)），结束它")
                process.terminate()
            }
        }
    }
}
