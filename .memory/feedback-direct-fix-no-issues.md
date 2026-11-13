---
name: feedback-direct-fix-no-issues
description: Snug 里 bug 直接修、重构直接做，不建 GitHub issue、不走 issue-driven；追溯靠 commit 信息
metadata:
  node_type: memory
  type: feedback
  originSessionId: f97709de-705a-489b-bb7a-7353b1fba51c
  modified: 2026-11-13T14:12:24.061Z
---

Snug 项目里发现 bug 直接修，设计不好直接重构，不先建 GitHub issue，也不走 issue-driven 流程。这条覆盖 AGENTS.md 里「凡事沉淀成 issue」的通用习惯。

**Why:** 主人原话：「是 bug 就直接修，不用弄成 issue，不用 issue-driven，直接做就行」。

**How to apply:** 来龙去脉写进 commit 信息（中文，改了什么、为什么），git log 就是追溯来源。只有需要主人决策或暂时做不了的事才在对话里提。需要真机或主人配合（手机连 UU）时直接开口。相关：[[project-positioning]]。
