---
name: project-release-identity
description: 发版用主人个人 Developer ID 签名公证；本项目 gh 硬绑定个人 GitHub 账号 zephyr4123
metadata:
  type: project
---

- **签名与公证**：用主人个人开发者账号的 `Developer ID Application`（Team ID `29898YBGWD`，本机唯一一张 Developer ID 证书；其他 Apple Development 证书不用于发版）。主人已有的公证流程可参照 `~/coding/personal/oink/packaging/macos/signing.py`（`xcrun notarytool` + keychain profile）。原项目用的是自签证书「UUDisplay Signing」、未公证，发版时要换掉。
- **GitHub 账号**：本机 gh 登录了不止一个账号。本项目在 `.claude/settings.local.json` 里用 `env.GH_CONFIG_DIR=~/.config/gh-zephyr4123` 硬绑定个人账号（该配置目录只登录了 zephyr4123；git 凭据走 `gh auth git-credential`，推送也跟着走个人账号）。2026-11-12 已在新会话里验证 `gh api user` 返回 zephyr4123。

**Why:** 主人在其他项目里会切换 gh 活跃账号，不硬绑定可能把本项目推到别的账号下（或反过来）。

**How to apply:** 涉及 gh / git 推送前不用手动切账号；如果 `gh api user --jq .login` 不是 zephyr4123，先停下查 `GH_CONFIG_DIR`，别直接推。建 GitHub 仓库、推送、发版前按红线先问主人。
