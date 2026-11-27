// 策略：配置 + 会话 → 此刻要哪些屏、每块的比例和行为。纯函数，规则只写在这里，换规则不动任何模块（docs/development.md「代码结构」）。
// - 远程开始（含断开后等重连的那段）就建出所有开着的屏：UU 每次新连接都从主屏开始，用户要在 UU 里手动选屏，屏得先在
// - 提前准备虚拟屏时所有开着的屏都常驻：CrossDesk 这类远控只在自己启动时认屏，连上后才建的屏它选不到。
//   远程结束时屏留着，Snug 放上去的窗口归位、用户在上面开的窗口挪回主屏，没人远程时指针进不去（看不见）
// - 远控只在自己启动时认屏、又没提前准备时，远程中不建屏：建了它也选不到，拓扑一变还会让 CrossDesk 的隐私屏失效。
//   状态里提示用户打开「提前准备虚拟屏」再重启远控
// - 这样的远程中，常驻的屏（提前准备的、设为主屏的）在手机上退出时只还原窗口、屏留着：撤了远程结束又建回来，换了编号，
//   远控就选不到了，得重启它（主人 11-23 定）。回到 Mac 原来的画面靠在远控里切屏；没接显示器的 Mac（issue #8）在这类远控下也是这样
// - 设为主屏的那块常驻，不等远程：UU 只在连上那一刻选一次屏，选的是当时的主屏；Snug 察觉连接时 UU 已在推 Mac 屏，
//   连上后再建、再设主屏都晚了。屏连接前就在、已经是主屏，每次连接才直接进去（11-18 实测，issue #28）
// - 换手接管落在重连等待期之内，算同一次远程，屏不撤不建（V12）
// - 程序不识别控制端：每块屏用什么比例、有什么行为，只取决于用户的设置，同样的设置每次结果都一样
// - 类别到行为的映射只在这里：手机、平板是触屏（屏上有面板、翻译手势、放大字号），电脑不是
import Foundation

public enum ScreenPlan {
    /// 此刻要的屏，按屏幕列表的顺序。remote：在不在远程（含断开后等重连的那段）；seesNewScreens：这次远程的远控认不认连上后才建的屏
    /// （只在启动时认屏的不认，见 RemoteIdentity.seesScreensOnlyAtLaunch）。
    /// trusted：没有辅助功能权限放不了窗口、翻译不了手势，一块都不建；preview：不等远程，建出所有开着的屏（--preview-screens）
    public static func wishes(config: AppConfig, remote: Bool, seesNewScreens: Bool = true, trusted: Bool, preview: Bool = false) -> [ScreenWish] {
        guard trusted else { return [] }
        let held = Set(withheld(config: config, remote: remote, seesNewScreens: seesNewScreens, preview: preview))
        // 预览时屏不是因为「提前准备」才在的：远程结束不收拾（开发者正看着），和不开提前准备的预览一样
        let prepared = config.keepScreensReady && !preview
        return shown(config).filter { (remote || preview || config.keepScreensReady || $0.id == config.mainScreen) && !held.contains($0.id) }.map { screen in
            var wish = ScreenWish(id: screen.id, spec: spec(of: screen), fit: fit(of: screen), behavior: behavior(screen.device.kind),
                                  main: config.mainScreen == screen.id, prepared: prepared)
            wish.staysOnDismiss = wish.resident && !seesNewScreens
            return wish
        }
    }

    /// 这次远程因为远控只在启动时认屏、又没提前准备而不建的屏（设为主屏的那块照常常驻，不算）：
    /// 状态里据此提示打开「提前准备虚拟屏」再重启远控，日志也记一句。参数同 wishes
    public static func withheld(config: AppConfig, remote: Bool, seesNewScreens: Bool, preview: Bool = false) -> [ScreenID] {
        guard remote, !seesNewScreens, !preview, !config.keepScreensReady else { return [] }
        return shown(config).map(\.id).filter { $0 != config.mainScreen }
    }

    private static func shown(_ config: AppConfig) -> ArraySlice<ScreenConfig> {
        config.screens.filter(\.enabled).prefix(ScreenConfig.limit)
    }

    /// 配置里的一项 → 屏的身份：竖横各一个产品号，像素上限和方向一致（V4、V5）
    public static func spec(of screen: ScreenConfig) -> ScreenSpec {
        let portrait = screen.orientation == .portrait
        return ScreenSpec(name: screen.name, productID: portrait ? ScreenSpec.portraitProductID : ScreenSpec.landscapeProductID,
                          serials: screen.serials, maxPixels: portrait ? ScreenFit.portraitPixels : ScreenFit.landscapePixels)
    }

    /// 配置里的一项 → 比例和档位（带上选的分辨率）
    public static func fit(of screen: ScreenConfig) -> ScreenFit { fit(screen.device, screen.orientation, width: screen.baseWidth) }

    /// 这台设备、这个方向的比例和档位（换型号时先算出来记日志）；width 是选的分辨率，nil 用默认
    public static func fit(_ device: DeviceChoice, _ orientation: Orientation, width: Int? = nil) -> ScreenFit {
        ScreenFit(device: device.screen, kind: device.kind, orientation: orientation, width: width)
    }

    /// 类别 → 行为（哪些类别算触屏见 DeviceKind.isTouch）
    public static func behavior(_ kind: DeviceKind) -> ScreenBehavior {
        kind.isTouch ? .touchScreen : .computer
    }
}
