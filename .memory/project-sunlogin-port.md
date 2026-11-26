---
name: project-sunlogin-port
description: 向日葵官方适配版 skyvense/snug-sunlogin（11-26 收进 README）：主人定对外称「向日葵官方适配」，答应对接人放醒目位置；与个人社区移植分开写
metadata:
  node_type: memory
  type: project
  originSessionId: f97709de-705a-489b-bb7a-7353b1fba51c
  modified: 2026-11-26T12:50:33.261Z
---

**来历**：11-19 前后向日葵官方找主人，问能否适配向日葵。当时适配层还没抽出来，主人婉拒，请他们的工程师自己做。11-26 对接人发来成品仓库 [skyvense/snug-sunlogin](https://github.com/skyvense/snug-sunlogin)。

**事实**：
- 支持 macOS 与 Windows；基于 Snug 2.5.0（含上游 v2.5.0 提交，不含 v2.6.0）
- 版本号自成一套（最新 v2.7.4，与我们的版本号无关）
- bundle id、数据目录、更新源与原版隔离，可同机共存
- 本仓库不测它，问题请对方仓库处理

**口径（主人 11-26 定）**：对外一律写「向日葵官方适配」（en: official port by Sunlogin；ja: 向日葵公式対応版）。对方 README 自称「贝锐技术人员以个人身份维护、非向日葵官方产品」，主人知情后仍定写官方。

**位置**：主人答应对接人放在醒目位置，README 三种语言在以下几处都有：
- 顶部「已支持的远控」，带「官方适配」角标，链接指向对方仓库
- IMPORTANT 第一条，含感谢
- 下载一节、系统要求
- 「社区移植」分「官方适配」「个人移植」两类
- 致谢

GitHub 简介里也写了。

**Why:** 这次适配不是我们做的，而是厂商官方介入，角色和个人移植不同；对外承诺过要醒目。

**How to apply:** 以后改 README 结构时，不要把它挪到不显眼的地方，也不要和个人移植混在一起。图标 `media/remote-sunlogin.2d91a469.png` 取自向日葵官方 AweSun 16.8.0 安装包，取法同 UU、CrossDesk 的图标（[[project-domestic-mirror]]）。相关：[[feedback-contributor-credit]]、[[project-remote-adapter]]。
