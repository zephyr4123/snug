---
name: project-release
description: 发版只走 scripts/snug（照 SpeakMore 的 ship）；个人 Developer ID（29898YBGWD）签名公证；gh 绑定 zephyr4123；GitHub 与国内源两处发布
metadata:
  node_type: memory
  type: project
  originSessionId: f97709de-705a-489b-bb7a-7353b1fba51c
  modified: 2026-11-13T14:11:31.273Z
---

- **一个入口**：构建、测试、打包、公证、发版都走 `scripts/snug`（check / app / install / dist / ship / mirror / media）。新步骤加成子命令或内部函数，不另起脚本。主人 11-13：「通过一行命令行就能去出包、去 release，千万别散在各处」。参照 SpeakMore（`~/coding/personal/reverse-anything`）的 ship：把关 → 检查 → 打包公证 → 上传 → 从下载地址核对 → 公开；断了只补没做完的那一步
- **签名公证**：个人 Developer ID Application（Team ID 29898YBGWD，本机唯一一张）。notarytool 档案与 SpeakMore 共用，名字在不进 git 的 `.machine.env`；档案在数据保护钥匙串里，`security find-generic-password` 搜不到，别据此说没有。苹果回 403「A required agreement is missing」是开发者协议待签，要账号持有人去 developer.apple.com 签
- **GitHub 账号**：本机 gh 登了多个账号，本项目用 `GH_CONFIG_DIR=~/.config/gh-zephyr4123` 绑定 zephyr4123（`.claude/settings.local.json` 和 `.machine.env` 里都有）。推送前 `gh api user --jq .login` 必须是 zephyr4123，不是就先停下。`scripts/snug` 导出了 `GH_REPO`：gh 不写明仓库时会挑 upstream，2.0.0 发版时差点发到原作者的仓库
- 合并主干、推送、发版前照红线先问主人。国内源见 [[project-domestic-mirror]]
