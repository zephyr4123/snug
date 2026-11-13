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
        // 私有 API（CGVirtualDisplay）头文件
        .target(name: "CGVirtualDisplayBridge"),
        .executableTarget(
            name: "Snug",
            dependencies: [
                "CGVirtualDisplayBridge",
                .product(name: "PermissionFlow", package: "PermissionFlow"),
                .product(name: "SystemSettingsKit", package: "PermissionFlow"),
                .product(name: "TourKit", package: "TourKit"),
            ],
            // 旧 App 代码第二阶段整体改写；在那之前停在 Swift 5 语言模式，避免为了严格并发检查去改界面逻辑
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
