---
name: project-known-issues
description: 接手时已知的两个 bug（外接屏闪烁循环、ColorSync 配置文件堆积）和三个社区修复 PR 的状态
metadata:
  node_type: memory
  type: project
  originSessionId: f97709de-705a-489b-bb7a-7353b1fba51c
  modified: 2026-11-13T04:05:43.689Z
---

接手时（2026-11-12）主人实测与排查得出：

1. **开「只保留虚拟屏」时屏幕反复闪烁**：关物理屏后误判 UU 断开 → 恢复物理屏 → 立刻又判连入 → 再关，循环数轮。⚠️ 更正（2026-11-12 20:01 实测）：原先记的「只在接 4K 外接屏时触发、只有内建屏不触发」是错的，拔掉外接屏、只有内建屏照样振荡。证据（macOS 统一日志，`/usr/bin/log show --predicate 'process == "UURemoteServer" OR process == "UURemote"'`）：两次振荡期间 UU 的采集/编码会话都是连续的（20:01:23.4→56.2 编码 1258 帧、丢 0 帧），中途那几次「断开」全是本工具误判。每次误判都落在 UURemote 打出「UIIntelligenceSupport agent connection cancelled」之后 1.5–1.9s；恢复物理屏后 0.01–0.02s，信号就随「Connection established」回来。17:46 那次还没建屏，也出现过一次误判，说明信号本身就会自己抖。根因：断开判定依赖覆盖窗口和 AX 表格这类 UI 代理信号，它们会自己抖，也会被本工具改拓扑扰动。PR #14 的连入确认 1.5s + 建屏冷却 8s 是补丁、不根治，推演显示还可能把振荡升级成「每轮拆屏重建」。根治方向：用会话级信号判断开（UU 的真实采集流），再加一个断路器（自身改拓扑后的屏蔽窗口；若出现「断开→恢复→马上重连」，本次会话就不再关物理屏）。注意：zsh 里 `log` 是内建命令，系统日志要写全路径 `/usr/bin/log`。
2. **ColorSync 配置文件只增不删**：每次建虚拟屏用随机 `serialNum`，macOS 视为新显示器，在 `/Library/ColorSync/Profiles/Displays/` 留一个 `UUyc companion · <设备>-<UUID>.icc`，从不回收；PR #14 作者那边攒到 176 个后 colorsyncd 常驻 90%～110% CPU。主人机器接手时已有 4 个（与建屏次数 1:1）。
3. **配置只在启动时读取**：`ConfigStore` 启动时读 `~/Library/Application Support/UUDisplay/config.json`，运行中改文件不生效且会被下次保存覆盖。

社区 PR 已拉成本地分支（都基于原 master `f5e45dc`，三者在 `DisplayManager.swift`、`Coordinator.swift`、`tests/monitor-main.swift` 上有重叠，合并会有冲突）：
- `pr/14-colorsync-and-oscillation`（+211/-47）：修 1 和 2，优先合。
- `pr/12-stale-restore-and-name-timeout`（+141/-8）：修残留恢复阻塞、控制端名称超时不触发。
- `pr/10-restore-sleep-and-fullscreen`（+767/-92）：修休眠交接时恢复失败、全屏时读不到控制端，改动大，单独评估。

主人的使用参数：iPhone 17 Pro Max 填 2400×1320（留出灵动岛和 UU 工具栏，画面居中），开「只保留虚拟屏」；别用 `⌃⌘F` 全屏（原项目 issue #11）。

**How to apply:** 修 bug 先从 PR #14 起；动连接检测或建屏逻辑时，用「接外接屏 + 只保留虚拟屏」这个场景回归。
