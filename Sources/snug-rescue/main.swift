// snug-rescue：救急命令行（取代 dispoff）。按记录恢复所有被熄灭的物理屏，可选还原布局。
// 用法：snug-rescue [--layout]
// 主程序崩溃、看门狗没开、物理屏还黑着时，用别的设备 ssh 上来或在占位屏上开终端运行
import Foundation
import SnugCore
import SnugDisplays

let usage = """
用法：snug-rescue [--layout]
  按 ~/Library/Application Support/Snug/disabled-displays.json 恢复所有被熄灭的物理屏
  --layout  同时按 layout.json 还原物理屏的显示模式与位置
退出码：0 全部成功（或没有需要恢复的）；1 有失败；2 参数错误

"""

let args = Array(CommandLine.arguments.dropFirst())
if args.contains("-h") || args.contains("--help") {
    print(usage, terminator: "")
    exit(0)
}
guard args.allSatisfy({ $0 == "--layout" }) else {
    FileHandle.standardError.write(Data(usage.utf8))
    exit(2)
}

let paths = SnugPaths.standard
let logSink = FileLogSink(url: paths.logFile, processTag: "snug-rescue")
Log.setSink(logSink)
var ok = true

let ledger = PhysicalDisplayLedger(url: paths.disabledDisplays)
let recorded = ledger.recorded()
if recorded.isEmpty {
    print("没有待恢复的物理屏记录")
} else {
    print("记录中待恢复的物理屏：\(recorded)")
    let result = ledger.restoreAll(pause: DisplayTiming.settleAfterPhysical)
    if !result.restored.isEmpty { print("✅ 已恢复：\(result.restored)") }
    if !result.failed.isEmpty {
        print("❌ 恢复失败：\(result.failed)（\(result.failure.map { "\($0)" } ?? "未知错误")），记录保留")
        ok = false
    }
    Log.info("snug-rescue 恢复物理屏：成功 \(result.restored)，失败 \(result.failed)")
}

if args.contains("--layout") {
    let store = DisplayLayoutStore(url: paths.layout)
    if let snapshot = store.pending() {
        Thread.sleep(forTimeInterval: DisplayTiming.settleAfterPhysical)
        switch store.restoreModes(snapshot) {
        case .success: print("✅ 显示模式已还原")
        case .failure(let f): print("⚠️ 还原显示模式失败（\(f)），继续还原位置")
        }
        Thread.sleep(forTimeInterval: DisplayTiming.settleAfterLayout)
        switch store.restoreOrigins(snapshot) {
        case .success: print("✅ 屏幕位置已还原，布局记录已删除")
        case .failure(let f):
            print("❌ 还原屏幕位置失败（\(f)），布局记录保留")
            ok = false
        }
    } else {
        print("没有布局记录")
    }
}

logSink.flush()
exit(ok ? 0 : 1)
