# Snug 图标资源

| 文件 | 用途 |
|---|---|
| `AppIcon.svg` | App 图标矢量源文件（1024 画布，已含 macOS 圆角底板与阴影） |
| `AppIcon-1024.png` | App 图标 1024×1024 PNG |
| `AppIcon.icns` | macOS 应用图标，放进 `.app/Contents/Resources/`，并在 Info.plist 设 `CFBundleIconFile = AppIcon` |

界面里的其它图标（菜单栏、设置页、手机屏）一律用 SF Symbols，不另外绘制。

## 设计说明

方案「双屏叠片」：青色横屏 = 被控电脑，蓝色竖屏 = 平板，交叠处深蓝 = 分辨率对齐。
配色：`#00EAFF → #0FC4FA`（电脑）、`#0A7CFF → #0057F0`（平板）、`#0441F5`（交叠）。
