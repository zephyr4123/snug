// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Snug",
    platforms: [.macOS(.v14)],
    dependencies: [
        // 权限引导：打开系统设置隐私页 + 拖拽授权悬浮面板（MIT，内置副本见 Vendor/PermissionFlow/VENDORED.md）
        .package(path: "Vendor/PermissionFlow"),
        // 首次启动功能导览（MIT，内置副本见 Vendor/TourKit/VENDORED.md）
        .package(path: "Vendor/TourKit"),
    ],
    targets: [
        // 纯逻辑：会话检测、会话生命周期、日志、持久化，以及可选的虚拟屏功能模块的决策部分。
        // 只依赖 Foundation（含 os.Logger），不碰 AppKit / CoreGraphics
        .target(name: "SnugCore"),
        // 私有 API（CGVirtualDisplay）头文件
        .target(name: "CGVirtualDisplayBridge"),
        // CoreGraphics 与私有 API 的副作用：实现 SnugCore 定义的 DisplayDriver，物理屏记账，布局快照与还原
        .target(name: "SnugDisplays", dependencies: ["SnugCore", "CGVirtualDisplayBridge"]),
        .executableTarget(
            name: "Snug",
            dependencies: [
                "SnugCore",
                "SnugDisplays",
                "CGVirtualDisplayBridge",
                .product(name: "PermissionFlow", package: "PermissionFlow"),
                .product(name: "SystemSettingsKit", package: "PermissionFlow"),
                .product(name: "TourKit", package: "TourKit"),
            ],
            // 旧 App 代码第二阶段整体改写；在那之前停在 Swift 5 语言模式，避免为了严格并发检查去改界面逻辑
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // 救急命令行：按记录恢复物理屏、还原布局（取代 dispoff）
        .executableTarget(name: "snug-rescue", dependencies: ["SnugCore", "SnugDisplays"]),
        .testTarget(name: "SnugCoreTests", dependencies: ["SnugCore"], resources: [.copy("Fixtures")]),
    ]
)
