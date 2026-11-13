// Snug：让用手机通过 UU远程 使用 Mac 更清晰、更方便。
// 这里只负责按启动模式组装；各模式见 LaunchMode（SnugCore）
import AppKit
import SnugCore

let mode: LaunchMode
do {
    mode = try LaunchMode.parse(Array(CommandLine.arguments.dropFirst()))
} catch {
    FileHandle.standardError.write(Data("\(error)\n\n\(LaunchMode.usage)\n".utf8))
    exit(2)
}

LaunchContext.mode = mode

switch mode {
case .watchdog:
    WatchdogProcess.run()
case .render(let target, let output):
    // 只渲染 PNG：不建 AppController、不起感知器、不碰显示器
    exit(MainActor.assumeIsolated { Renderer.run(target, output: output) } ? 0 : 1)
case .dumpUU:
    exit(MainActor.assumeIsolated { UUDump.run() })
case .simulate, .stress:
    MainActor.assumeIsolated { SimulationRunner.run(mode) }
case .app:
    let paths = SnugPaths.standard
    Log.setSink(FileLogSink(url: paths.logFile))
    let app = NSApplication.shared
    let delegate = MainActor.assumeIsolated { AppDelegate(paths: paths) }
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
