// 策略：配置 + 会话 → 此刻要哪些屏、每块的比例和行为。纯函数，规则只写在这里，换规则不动任何模块（docs/development.md「代码结构」）。
// - 远程开始（含断开后等重连的那段）就建出所有开着的屏：UU 每次新连接都从主屏开始，用户要在 UU 里手动选屏，屏得先在
// - 设为主屏的那块常驻，不等远程：UU 只在连上那一刻选一次屏，选的是当时的主屏；Snug 察觉连接时 UU 已在推 Mac 屏，
//   连上后再建、再设主屏都晚了。屏连接前就在、已经是主屏，每次连接才直接进去（11-18 实测，issue #28）
// - 换手接管落在重连等待期之内，算同一次远程，屏不撤不建（V12）
// - 程序不识别控制端：每块屏用什么比例、有什么行为，只取决于用户的设置，同样的设置每次结果都一样
// - 类别到行为的映射只在这里：手机、平板是触屏（屏上有面板、翻译手势、放大字号），电脑不是
import Foundation

public enum ScreenPlan {
    /// 此刻要的屏，按屏幕列表的顺序。remote：在不在远程（含断开后等重连的那段），不在远程时只要设为主屏的那块；
    /// trusted：没有辅助功能权限放不了窗口、翻译不了手势，一块都不建；preview：不等远程，建出所有开着的屏（--preview-screens）
    public static func wishes(config: AppConfig, remote: Bool, trusted: Bool, preview: Bool = false) -> [ScreenWish] {
        guard trusted else { return [] }
        let shown = config.screens.filter(\.enabled).prefix(ScreenConfig.limit)
        return shown.filter { remote || preview || $0.id == config.mainScreen }.map { screen in
            ScreenWish(id: screen.id, spec: spec(of: screen), fit: fit(of: screen), behavior: behavior(screen.device.kind),
                       main: config.mainScreen == screen.id)
        }
    }

    /// 配置里的一项 → 屏的身份：竖横各一个产品号，像素上限和方向一致（V4、V5）
    public static func spec(of screen: ScreenConfig) -> ScreenSpec {
        let portrait = screen.orientation == .portrait
        return ScreenSpec(name: screen.name, productID: portrait ? ScreenSpec.portraitProductID : ScreenSpec.landscapeProductID,
                          serials: screen.serials, maxPixels: portrait ? ScreenFit.portraitPixels : ScreenFit.landscapePixels)
    }

    /// 配置里的一项 → 比例和档位
    public static func fit(of screen: ScreenConfig) -> ScreenFit { fit(screen.device, screen.orientation) }

    /// 这台设备、这个方向的比例和档位（换型号时先算出来记日志）
    public static func fit(_ device: DeviceChoice, _ orientation: Orientation) -> ScreenFit {
        ScreenFit(device: device.screen, kind: device.kind, orientation: orientation)
    }

    /// 类别 → 行为（哪些类别算触屏见 DeviceKind.isTouch）
    public static func behavior(_ kind: DeviceKind) -> ScreenBehavior {
        kind.isTouch ? .touchScreen : .computer
    }
}
