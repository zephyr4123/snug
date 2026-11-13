---
name: feedback-release-cli
description: 出包、发版收进一个 CLI 入口（scripts/snug），照 SpeakMore 的 ship 设计；不许散成各处的脚本
metadata:
  node_type: memory
  type: feedback
  originSessionId: f97709de-705a-489b-bb7a-7353b1fba51c
  modified: 2026-11-13T08:20:11.651Z
---

构建、测试、打包、公证、发版都走 `scripts/snug <命令>` 这一个入口（check / app / install / dist / ship）。新增出包相关的步骤加成它的子命令或内部函数，不另起脚本文件。

**Why:** 主人 2026-11-13 原话：「把出包流程通过 CLI 统一收纳起来，不要散成各处的脚本」「通过一行命令行就能去出包、去 release，千万别散在各处」。参照的是主人自己的 SpeakMore（源码在 `~/coding/personal/reverse-anything`，`npm run ship`）：把关 → 全量检查 → 打包签名公证 → 上传 → 从下载地址核对 → 公开；断了只补没做完的一步，不重新打包；本机才有的名字放不进 git 的 `.machine.env`。

**How to apply:** 改出包流程先看 `scripts/snug` 和 README「开发」一节，跟着它的结构改；README 的命令表随之更新。发版（ship 会推 GitHub Release）前照红线先问主人。相关：[[project-release-identity]]。
