---
name: project-refactor-latitude
description: Snug 尚无线上用户：该删就删、该改就改，不留兼容；2026-11-12 主人批准全面重构
metadata:
  node_type: memory
  type: project
  originSessionId: f97709de-705a-489b-bb7a-7353b1fba51c
  modified: 2026-11-13T04:13:07.392Z
---

截至 2026-11-12 Snug 还没发过版、没有线上用户。原项目 UUyc-companion 的用户不算我们的兼容包袱；已装原版的机器要考虑共存或替换，见 [[project-release-identity]]。2026-11-12 主人批准对全仓做全面重构（分支 `refactor/snug`）。

**Why:** 主人原话：「咱们这个没有任何生产上的用户需要照顾，该删的删，该改的改。不要只是去加、去兼容，觉得不好的就直接重构、直接删掉」「bug 还是挺多的，而且工程审美上的问题也没照顾到，就全面重构一下吧」。

**How to apply:**
- 不写兼容层：旧 session.json 的 `[x,y]` 格式、UUDisplay 配置目录、原版 bundle ID 这类都不用保留。
- 不好的设计直接重写或删掉，不要为了「改动小」去打补丁叠加。
- 已承载的硬约束（WindowServer 崩溃教训、释放前存活 ≥2.5s 等）要保留，并用测试守住。
- 首版发布、有了用户之后，重新评估这条。

相关：[[project-known-issues]]、[[feedback-workflow-scale]]、[[feedback-direct-fix-no-issues]]。
