---
name: project-release
description: 发版只走 scripts/snug（照 SpeakMore 的 ship）；个人 Developer ID（29898YBGWD）签名公证；gh 绑定 zephyr4123；GitHub 与国内源两处发布
metadata:
  node_type: memory
  type: project
  originSessionId: f97709de-705a-489b-bb7a-7353b1fba51c
  modified: 2026-11-14T14:10:00.000Z
---

- **一个入口**：构建、测试、打包、公证、发版都走 `scripts/snug`（check / app / install / dist / ship / mirror / media）。新步骤加成子命令或内部函数，不另起脚本。主人 11-13：「通过一行命令行就能去出包、去 release，千万别散在各处」。参照 SpeakMore（`~/coding/personal/reverse-anything`）的 ship：把关 → 检查 → 打包公证 → 上传 → 从下载地址核对 → 公开；断了只补没做完的那一步
- **签名公证**：个人 Developer ID Application（Team ID 29898YBGWD，本机唯一一张）。notarytool 档案与 SpeakMore 共用，名字在不进 git 的 `.machine.env`；档案在数据保护钥匙串里，`security find-generic-password` 搜不到，别据此说没有。苹果回 403「A required agreement is missing」是开发者协议待签，要账号持有人去 developer.apple.com 签
- **GitHub 账号**：本机 gh 登了多个账号，本项目用 `GH_CONFIG_DIR=~/.config/gh-zephyr4123` 绑定 zephyr4123（`.claude/settings.local.json` 和 `.machine.env` 里都有）。推送前 `gh api user --jq .login` 必须是 zephyr4123，不是就先停下。`scripts/snug` 导出了 `GH_REPO`：gh 不写明仓库时会挑 upstream，2.0.0 发版时差点发到原作者的仓库
- **应用内更新**（2026-11-14 起）：dist 顺带用 `snug-release pack` 打 `Snug-<版本>.pack`，ship 用标签说明写 `update.json`，两处都传。分块更新是主人拍板的：差分补丁要按版本配对，主人嫌「产生一堆中间产物」，宁可多下一点（实测分块对 Snug 几乎不省流量，1.1 MB 对整包 1.2 MB），别再提差分。`firstUpdatable` = 2.1.0（Sources/SnugRelease）。2.1.0 于 2026-11-14 发布，本机实测从真实的腾讯云自更新：2.0.1 → 2.1.0 只取了 3 段 132 KB，换上的和正式 dmg 里的逐字节一致、Gatekeeper 认可
- **本机实测更新**：别往 COS 传测试文件。临时把 `UpdateSource.tencentBase` 改成 `http://127.0.0.1:8765/snug`、VERSION 设成旧版本号 install；另打一个新版本号的 App，用临时本地标签跑 `snug-release pack/feed` 摆成国内源的目录，起一个支持 Range 的本地服务器；点「立即更新」后看日志和 Info.plist。测完 `git checkout` 还原、删临时标签、重装。SwiftUI 的按钮在辅助功能里没有标题，osascript 点 `last button of group 1 of window "软件更新"`（「立即更新」在最右）。2.1.0 实测时有一次按序号点完窗口没了、也没开始更新，日志里没有更新记录，第二次正常，原因未查明；下次有新版本时留意真机点击是否复现
- 合并主干、推送、发版前照红线先问主人。国内源见 [[project-domestic-mirror]]
