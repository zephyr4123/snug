---
name: feedback-workflow-scale
description: 起 Workflow 之前先跟主人确认；默认自己小步快跑，不滥用 Workflow；真要起时 agent 5 个左右、链路两段以内
metadata:
  node_type: memory
  type: feedback
  originSessionId: f97709de-705a-489b-bb7a-7353b1fba51c
  modified: 2026-11-14T13:17:47.156Z
---

1. **起之前先确认**：任何事要起 Workflow，先跟主人说清楚打算怎么编排、为什么值得，等主人点头再起。不是不让起，是起之前要问（即使 ultracode 开着也一样）
2. **默认自己干**：读代码、做设计、写实现，自己小步快跑就行，不是所有活都要 Workflow
3. **真要起时控制规模**：一次 5 个左右，链路两段以内：并行分析 → 一个核实者统一逐条核实。不要每条 finding 派 N 个反驳者，也不要多轮 loop-until-dry 的长链

**Why:** 2026-11-13 主人：「一定要注意控制 agent 的数量，可千万不要把额度给打爆炸了」「链路太长了就会很慢，而且很消耗额度」。2026-11-14 做自动更新功能前我正要起 Workflow 调研，被主人打断：「不要滥用 workflow，咱们用小步快跑的策略去做，你一个人的能力也是很强的」「以后起 workflow 去做任何事之前，你得先跟我确认」。

**How to apply:** 想起 Workflow 时先停下，用一两句话问主人（打算几个 agent、各干什么）；没得到确认就自己读、自己做。与 [[skill-routing-general]] 里的编排 skill 配合使用。
