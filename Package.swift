// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Snug",
    platforms: [.macOS(.v14)],
    dependencies: [
        // 权限引导：打开系统设置隐私页 + 拖拽授权悬浮面板（MIT，内置副本见 Vendor/PermissionFlow/VENDORED.md）
        .package(path: "Vendor/PermissionFlow"),
    ],
    targets: [
        // 纯逻辑：会话检测、手机屏的调度（PhoneDesk）、手势翻译、持久化、日志、启动参数。
        // 只依赖 Foundation（含 os.Logger）和 CoreGraphics 的几何类型，不碰 AppKit、不调系统接口，全部可以用假的系统能力测试
        .target(name: "SnugCore"),
        // 私有 API（CGVirtualDisplay）头文件
        .target(name: "CGVirtualDisplayBridge"),
        // 系统层：建屏撤屏、切模式、搬窗口、发按键、事件监听。实现 SnugCore 定义的系统能力
        .target(name: "SnugSystem", dependencies: ["SnugCore", "CGVirtualDisplayBridge"]),
        .executableTarget(
            name: "Snug",
            dependencies: [
                "SnugCore",
                "SnugSystem",
                .product(name: "PermissionFlow", package: "PermissionFlow"),
                .product(name: "SystemSettingsKit", package: "PermissionFlow"),
            ]
        ),
        .testTarget(name: "SnugCoreTests", dependencies: ["SnugCore"], resources: [.copy("Fixtures")]),
    ]
)
