---
name: feedback-workflow-scale
description: 用 Workflow 做多视角分析时控制 agent 数量、链路要短，速度与额度要平衡，不搞每条结论派多个反驳者
metadata:
  node_type: memory
  type: feedback
  originSessionId: f97709de-705a-489b-bb7a-7353b1fba51c
  modified: 2026-11-13T03:39:02.859Z
---

用 Workflow 做多视角分析/审查时，agent 数量要克制（一次 5 个左右为宜），链路尽量两段以内：并行分析 → 一个核实者统一逐条核实。不要每条 finding 派 N 个反驳者、也不要多轮 loop-until-dry 的长链。

**Why:** 主人原话：「一定要注意控制 agent 的数量，可千万不要把额度给打爆炸了」「起一大堆 agent 又去反驳啥的，链路太长了就会很慢，而且很消耗额度」——速度和额度都要兼顾。

**How to apply:** 设计 workflow 时先按维度切 3~5 路并行；需要核实时汇总后交给 1 个独立核实者（满足 AGENTS.md「finding 逐条核实」的纪律，但不放大成扇出）；不需要核实的产出（如设计建议）不挡住核实阶段。与 [[skill-routing-general]] 里的编排 skill 配合使用。
