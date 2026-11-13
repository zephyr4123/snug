---
name: project-known-issues
description: 接手时已知的两个 bug（外接屏闪烁循环、ColorSync 配置文件堆积）和三个社区修复 PR 的状态
metadata:
  type: project
---

接手时（2026-11-12）主人实测与排查得出：

1. **外接显示器时屏幕反复闪烁**：开「远程时只保留虚拟屏」且接着 4K 外接屏时，关掉两块物理屏后 0.3 秒就误判 UU 断开 → 恢复 → 再判连入 → 再关，循环 4 轮。根因（PR #14 作者的分析，与主人日志吻合）：`UUConnectionState` 断开有 1.5s 防抖、连入没有防抖，而本工具自己改显示拓扑会让 UU 的覆盖窗口短暂重建，形成自激振荡。只接内建屏时不触发。
2. **ColorSync 配置文件只增不删**：每次建虚拟屏用随机 `serialNum`，macOS 视为新显示器，在 `/Library/ColorSync/Profiles/Displays/` 留一个 `UUyc companion · <设备>-<UUID>.icc`，从不回收；PR #14 作者那边攒到 176 个后 colorsyncd 常驻 90%～110% CPU。主人机器接手时已有 4 个（与建屏次数 1:1）。
3. **配置只在启动时读取**：`ConfigStore` 启动时读 `~/Library/Application Support/UUDisplay/config.json`，运行中改文件不生效且会被下次保存覆盖。

社区 PR 已拉成本地分支（都基于原 master `f5e45dc`，三者在 `DisplayManager.swift`、`Coordinator.swift`、`tests/monitor-main.swift` 上有重叠，合并会有冲突）：
- `pr/14-colorsync-and-oscillation`（+211/-47）：修 1 和 2，优先合。
- `pr/12-stale-restore-and-name-timeout`（+141/-8）：修残留恢复阻塞、控制端名称超时不触发。
- `pr/10-restore-sleep-and-fullscreen`（+767/-92）：修休眠交接时恢复失败、全屏时读不到控制端，改动大，单独评估。

主人的使用参数：iPhone 17 Pro Max 填 2400×1320（留出灵动岛和 UU 工具栏，画面居中），开「只保留虚拟屏」；别用 `⌃⌘F` 全屏（原项目 issue #11）。

**How to apply:** 修 bug 先从 PR #14 起；动连接检测或建屏逻辑时，用「接外接屏 + 只保留虚拟屏」这个场景回归。
