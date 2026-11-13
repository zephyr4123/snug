// Snug：用手机通过 UU远程 用 Mac 时，窗口铺满手机、字够大、手势顺手。
// 这里只负责按启动模式组装；各模式见 LaunchMode（SnugCore）
import AppKit
import SnugCore
import SnugSystem

let mode: LaunchMode
do {
    mode = try LaunchMode.parse(Array(CommandLine.arguments.dropFirst()))
} catch {
    FileHandle.standardError.write(Data("\(error)\n\n\(LaunchMode.usage)\n".utf8))
    exit(2)
}

switch mode {
case .render(let target, let output):
    // 只渲染 PNG：不建 AppController、不起感知器、不碰屏幕和窗口
    exit(MainActor.assumeIsolated { Renderer.run(target, output: output) } ? 0 : 1)
case .dumpUU:
    exit(MainActor.assumeIsolated { UUDump.run() })
case .setMode(let display, let width, let height):
    Log.setSink(FileLogSink(url: SnugPaths.standard.logFile, processTag: "帮手"))
    let outcome = DisplayMode.switchToHiDPI(display, width: width, height: height)
    Log.info("切屏幕 #\(display) 到 2 倍 \(width)x\(height)：\(outcome)")
    Log.flush()
    exit(outcome == .switched ? 0 : 1)
case .app, .previewPhone:
    let paths = SnugPaths.standard
    Log.setSink(FileLogSink(url: paths.logFile))
    let app = NSApplication.shared
    let delegate = MainActor.assumeIsolated { AppDelegate(paths: paths, previewPhone: mode == .previewPhone) }
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
