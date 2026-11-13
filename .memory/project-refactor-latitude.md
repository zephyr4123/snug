---
name: project-refactor-latitude
description: Snug 尚无线上用户，允许随时做手术刀式重构；全面审查要同时覆盖 bug 与工程审美
metadata:
  node_type: memory
  type: project
  originSessionId: f97709de-705a-489b-bb7a-7353b1fba51c
  modified: 2026-11-13T03:39:08.045Z
---

截至 2026-11-12 Snug 还没发过版、没有线上用户（原项目 UUyc-companion 的用户不算我们的兼容包袱，但已装原版的机器要考虑共存/替换，见 [[project-release-identity]]）。主人明确：既然已经承接，手术刀式重构可以随时做。

**Why:** 主人原话：「咱们既然承接过来了，这种手术刀式的重构也是可以随时去做的，反正又没有线上用户这一说」；起 workflow 扫的时候「就扫得彻底一点」——有 bug 就报，也要看是否符合优雅的工程抽象。

**How to apply:** 审 PR 或排查时顺带做全仓扫描（bug + 工程设计），重构建议要边界清楚、可单独落地；仍遵守 AGENTS.md 红线 9（大重构单独立项、单独分支）。首版发布后重新评估这条（有用户后要考虑配置/session.json 等的兼容）。相关：[[project-known-issues]]、[[feedback-workflow-scale]]。
