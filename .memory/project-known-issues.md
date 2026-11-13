---
name: project-known-issues
description: 接手时的两个 bug 在 2.0 已解决；残留 25 个 ColorSync 配置文件待主人授权 sudo 清理；社区 PR 分支已删
metadata:
  node_type: memory
  type: project
  originSessionId: f97709de-705a-489b-bb7a-7353b1fba51c
  modified: 2026-11-13T04:05:43.689Z
---

接手时（2026-11-12）的已知问题，到 2.0.0 发布（2026-11-13）时的状态：

1. **开「只保留虚拟屏」时屏幕反复闪烁**：已随旧流程消失。原因是断开判定只靠覆盖窗口和 UU 表格这类会自己抖的界面信号，加上本工具改屏幕拓扑扰动 UU。2.0 删掉了设主屏、关物理屏，断开判定改用 UU 的推流日志（会话级信号），本工具加撤屏后有静默期。
2. **ColorSync 配置文件只增不删**：已止住。原版每次建屏用随机 serialNum，macOS 每次多存一份 `.icc`；2.0 的手机屏只用三个固定身份（`PhoneScreenSpec.serials`）。但接手前后攒下的旧文件还在：2026-11-13 数到 `/Library/ColorSync/Profiles/Displays/` 下名字含 UUyc / Snug 的 25 个，删要 sudo，**待主人同意后清理**（文件太多时 colorsyncd 会常驻高 CPU）。
3. **社区 PR**：#10、#12、#14 的思路已吸收进 2.0（「关于」页致谢 bubble、gencheng liu、Rongzheng Liu），本地评估用的 `pr/*` 分支 2026-11-13 已删，原 PR 仍在上游 aoyamashou/UUyc-companion。

**How to apply:** 主人提到 colorsyncd 占 CPU 或要清理系统残留时，先列出这批 `.icc` 给主人看，经同意再用 sudo 删；不要动非 UUyc / Snug 的显示器配置文件。注意：zsh 里 `log` 是内建命令，查系统日志要写全路径 `/usr/bin/log`。
