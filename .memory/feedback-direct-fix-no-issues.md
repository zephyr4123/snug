---
name: feedback-direct-fix-no-issues
description: Snug 项目里 bug 直接修、重构直接做，不建 GitHub issue、不走 issue-driven
metadata:
  node_type: memory
  type: feedback
  originSessionId: f97709de-705a-489b-bb7a-7353b1fba51c
  modified: 2026-11-13T04:13:11.763Z
---

在 Snug 项目里，发现 bug 直接修，觉得设计不好就直接重构，不用先建 GitHub issue，也不走 issue-driven 流程。这条覆盖 AGENTS.md 里「凡事沉淀成 issue」的通用习惯。

**Why:** 主人原话：「是 bug 就直接修，不用弄成 issue，不用 issue-driven，直接做就行」。

**How to apply:**
- 修复的来龙去脉写进 commit 信息（中文，写清改了什么、为什么）。git log 就是这个项目的追溯来源。
- 只有需要主人决策、或者暂时做不了的事，才在对话里提出来。
- 测试需要真机或主人配合（手机连 UU）时直接开口。主人本机有全套 Xcode 和模拟器，可以随时用。

相关：[[project-refactor-latitude]]。
