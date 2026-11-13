// --simulate / --stress：用脚本化的 UU 信号驱动完整的 AppController，会真的建虚拟屏、熄灭物理屏。
// 只在没人远程这台 Mac 时手动运行。配置只读不写：在内存里打开虚拟屏，没填分辨率的设备用测试尺寸
import AppKit
import SnugCore

/// 脚本化的信号源：connected 是此刻的控制端名称，nil 表示没人连着
@MainActor
final class ScriptedSignals: SignalSource {
    var connected: String?

    func start() {}
    func stop() {}
    func requestMainWindow() {}

    func sample(now: Date) -> UUSample {
        UUSample(signals: UUSignals(overlayVisible: connected != nil, controllers: connected.map { [$0] } ?? [],
                                    captureActive: nil),
                 streamingDisplay: nil)
    }
}

@MainActor
enum SimulationRunner {
    static let testProfile = DeviceProfile(name: "", kind: .tablet, width: 2360, height: 1640)
    static let stressDevices = ["iPad Air", "OPPO Pad 3", "iPhone 17", "MacBook Air"]

    static func run(_ mode: LaunchMode) -> Never {
        let paths = SnugPaths.standard
        let sink = FileLogSink(url: paths.logFile, processTag: "模拟")
        Log.setSink(sink)
        let names: [String]
        switch mode {
        case .simulate(let n, _): names = n
        case .stress: names = stressDevices
        default: fatalError("SimulationRunner 只处理 --simulate / --stress")
        }
        let signals = ScriptedSignals()
        let controller = AppController(paths: paths, store: ConfigStore(url: nil, initial: config(for: names, paths: paths)),
                                       sensor: signals, watchdog: nil)
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        controller.start()
        let end: TimeInterval
        switch mode {
        case .simulate(_, let seconds): end = simulate(names, seconds: seconds, signals: signals)
        case .stress(let rounds, let slow): end = stress(rounds: rounds, slow: slow, signals: signals)
        default: end = 0
        }
        after(end) {
            Log.info("—— 模拟结束，收尾退出")
            controller.finishForQuit(stopWatchdog: false, timeout: 15) {
                sink.flush()
                exit(0)
            }
        }
        app.run()
        exit(0)
    }

    /// "A>B"：先按 A 连入，3 秒后控制端变成 B；seconds 秒后断开，再等 3 秒收尾
    private static func simulate(_ names: [String], seconds: TimeInterval, signals: ScriptedSignals) -> TimeInterval {
        Log.info("—— 模拟连入 \(names.joined(separator: " → "))，\(Int(seconds)) 秒后断开")
        signals.connected = names.first
        for (i, name) in names.dropFirst().enumerated() {
            after(3 * Double(i + 1)) { signals.connected = name }
        }
        after(seconds) {
            Log.info("—— 模拟断开")
            signals.connected = nil
        }
        return seconds + 3
    }

    /// 随机连入 / 换设备 / 断开，间隔 0.3–6 秒，制造上一轮没收完就进入下一轮的情况；slow：每段 2.5–5 秒，确保走到熄屏
    private static func stress(rounds: Int, slow: Bool, signals: ScriptedSignals) -> TimeInterval {
        func hold(_ r: ClosedRange<Double>) -> Double { slow ? .random(in: 2.5...5) : .random(in: r) }
        var t = 0.0
        for round in 1...rounds {
            let a = stressDevices.randomElement() ?? "iPad Air"
            after(t) { Log.info("—— 压测第 \(round)/\(rounds) 轮：连入 \(a)"); signals.connected = a }
            t += hold(0.3...4)
            if Bool.random(), let b = stressDevices.randomElement() {
                after(t) { Log.info("—— 换设备为 \(b)"); signals.connected = b }
                t += hold(0.3...3)
            }
            after(t) { Log.info("—— 断开"); signals.connected = nil }
            t += hold(0.3...6)
        }
        return t + 1
    }

    /// 读现有配置（只读），在内存里打开虚拟屏；脚本里的设备没填分辨率就用测试尺寸
    private static func config(for names: [String], paths: SnugPaths) -> AppConfig {
        var c = ConfigStore(url: paths.config).config
        c.virtualDisplayEnabled = true
        c.paused = false
        for name in names where !(c.device(named: name).map { $0.kind != .computer && $0.hasSize } ?? false) {
            var p = testProfile
            p.name = name
            c.devices.removeAll { $0.name == name }
            c.devices.append(p)
        }
        return c
    }

    private static func after(_ seconds: TimeInterval, _ body: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { MainActor.assumeIsolated(body) }
    }
}
