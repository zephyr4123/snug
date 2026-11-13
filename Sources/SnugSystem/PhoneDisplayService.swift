// 手机屏的建、撤（CGVirtualDisplay 私有接口）。实测过的做法（见记忆 project-phone-screen）：
// - maxPixels 正好等于 2 倍像素、只给一个模式、hiDPI 打开，系统上线时多半就是 2 倍
// - 但系统按「当前这组屏幕」记模式，不是 2 倍时交给帮手进程去切（主程序亲自切会让释放拖 40 秒以上）
// - 建好不上线就换备用身份
// - 在主线程建和释放；释放时不能留局部强引用，否则不会真正释放
import AppKit
import CGVirtualDisplayBridge
import SnugCore

@MainActor
public final class PhoneDisplayService: PhoneDisplays {
    static let onlineTimeout: TimeInterval = 6
    static let offlineTimeout: TimeInterval = 10

    private var displays: [DisplayID: CGVirtualDisplay] = [:]
    /// 帮手进程：就是 Snug 自己，带 --set-mode 运行
    private let helper: URL

    public init(helper: URL) { self.helper = helper }

    public func create(_ spec: PhoneScreenSpec) async throws -> DisplayID {
        for serial in spec.serials {
            guard let display = make(spec, serial: serial) else {
                Log.warn("手机屏（serial=\(serial)）建不出来，换备用身份")
                continue
            }
            let id = display.displayID
            displays[id] = display
            guard await wait(id, online: true, timeout: Self.onlineTimeout) else {
                Log.warn("手机屏 #\(id)（serial=\(serial)）建好 \(Int(Self.onlineTimeout)) 秒没上线，换备用身份")
                await retire(id)
                continue
            }
            // 刚上线时模式还在变，等它定下来再看是不是 2 倍
            try? await Task.sleep(for: .seconds(0.8))
            if await !ensureHiDPI(id, spec) { Log.warn("手机屏 #\(id) 不是 2 倍：\(DisplayMode.describe(id))") }
            return id
        }
        throw PhoneScreenError.neverOnline
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

    public func ensureHiDPI(_ id: DisplayID, _ spec: PhoneScreenSpec) async -> Bool {
        if DisplayMode.isHiDPI(id) { return true }
        Log.info("手机屏 #\(id) 现在是 \(DisplayMode.describe(id))，让帮手进程切到 2 倍")
        let status = await runHelper(id, spec)
        try? await Task.sleep(for: .seconds(1))
        let ok = DisplayMode.isHiDPI(id)
        if ok {
            Log.info("手机屏 #\(id) 已是 2 倍：\(DisplayMode.describe(id))")
        } else {
            Log.warn("帮手进程切 2 倍没成（退出码 \(status.map(String.init) ?? "启动失败")），现在 \(DisplayMode.describe(id))")
        }
        return ok
    }

    public func windowArea(_ id: DisplayID) -> CGRect? {
        guard let screen = Screens.screen(for: id) else { return nil }
        var area = Screens.axRect(fromAppKit: screen.visibleFrame)
        area.size.height -= PhoneScreenSpec.homeBarHeight
        return area
    }

    // MARK: 内部

    private func make(_ spec: PhoneScreenSpec, serial: UInt32) -> CGVirtualDisplay? {
        let descriptor = CGVirtualDisplayDescriptor()
        descriptor.name = PhoneScreenSpec.name
        descriptor.maxPixelsWide = UInt32(spec.pixelWidth)
        descriptor.maxPixelsHigh = UInt32(spec.pixelHeight)
        descriptor.sizeInMillimeters = CGSize(width: spec.millimeters.width, height: spec.millimeters.height)
        descriptor.vendorID = PhoneScreenSpec.vendorID
        descriptor.productID = PhoneScreenSpec.productID
        descriptor.serialNum = serial
        guard let display = autoreleasepool(invoking: { CGVirtualDisplay(descriptor: descriptor) }) else { return nil }
        let settings = CGVirtualDisplaySettings()
        settings.hiDPI = true
        settings.modes = [CGVirtualDisplayMode(width: UInt(spec.width), height: UInt(spec.height), refreshRate: 60)]
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

    /// 起帮手进程切模式，等它退出；返回退出码，起不来返回 nil
    private func runHelper(_ id: DisplayID, _ spec: PhoneScreenSpec) async -> Int32? {
        let process = Process()
        process.executableURL = helper
        process.arguments = ["--set-mode", "\(id)", "\(spec.width)", "\(spec.height)"]
        return await withCheckedContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                Log.error("帮手进程起不来（\(helper.path)）：\(error)")
                continuation.resume(returning: nil)
            }
        }
    }
}
