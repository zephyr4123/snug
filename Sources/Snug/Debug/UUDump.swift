// --dump-uu：打印从 UU远程 读到的东西和此刻的屏幕。只读，不点 UU、不碰屏幕
import CoreGraphics
import Foundation
import SnugCore
import SnugSystem

@MainActor
enum UUDump {
    static func run() -> Int32 {
        print("覆盖窗口：\(UURemoteApp.overlayVisible() ? "在屏" : "没有")")
        printDisplays()
        guard AX.isTrusted else {
            print("没有辅助功能权限，读不到 UU远程 的界面")
            return 1
        }
        guard let pid = UURemoteApp.pid() else {
            print("UU远程 没有在运行")
            return 1
        }
        guard let rows = UUAccessibility.rows(pid: pid) else {
            print("表格：读不到（UU远程 没有窗口，或界面超出遍历上限）→ 控制端按手机处理")
            return 0
        }
        // 每行原文都打出来：认不出控制端时，看这里就知道 UU 此刻显示的是什么
        print("表格：\(rows.count) 行")
        for texts in rows { print("  \(texts.joined(separator: " | "))") }
        guard case .shown(let names) = ControllerTable(rows: rows) else {
            print("控制端：未识别（没被控时 UU 不显示控制端；远程中也这样，说明认不出 UU 的界面）→ 按手机处理")
            return 0
        }
        print("控制端：")
        for name in names { print("  \(name) → \(ControllerKind(name: name).wantsPhoneScreen ? "加手机屏" : "电脑，不加")") }
        return 0
    }

    private static func printDisplays() {
        var count: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetOnlineDisplayList(count, &ids, &count)
        print("屏幕：")
        for id in ids.prefix(Int(count)) {
            let mine = CGDisplayVendorNumber(id) == PhoneScreenSpec.vendorID ? "（Snug 手机屏）" : ""
            print("  #\(id) \(Screens.name(of: id))\(mine) \(DisplayMode.describe(id))")
        }
    }
}
