---
name: project-domestic-mirror
description: 国内源 dl.zephyrxiang.com/snug/（腾讯云 COS + CDN，与 SpeakMore 共用桶、按 snug/ 隔离）放安装包和 README 媒体；GitHub README 不播外链视频；证书 2027-01-12 到期
metadata:
  node_type: memory
  type: project
  originSessionId: f97709de-705a-489b-bb7a-7353b1fba51c
  modified: 2026-11-13T14:12:02.864Z
---

2026-11-13 主人定的：安装包要有国内源（以后官网也从这里取，GitHub Release 照留）；README 的图片、视频也放这里，用原画质。

- **摆法**：前缀 `https://dl.zephyrxiang.com/snug/`，和 SpeakMore 发布包同一个桶（桶名、地域、凭据名在不进 git 的 `.machine.env`，这份记忆会公开，别写进来）。`v<版本>/` 发过不改；`latest/Snug.dmg` 是固定的最新版地址，缓存 5 分钟、只往新版本换；`media/<名>.<指纹>.<后缀>` 放 README 媒体
- **命令**：`ship` 发版时自动传；`mirror <版本>` 补传 GitHub 上已公开的版本；`media <文件…>` 传媒体并打出地址。对象都带 sha256 元数据，重跑一样就跳过、不一样就拒绝
- **README 媒体**：GitHub 会删掉 `<video>`，录屏在 README 里用 animated WebP（经 GitHub 图片代理要 ≤5 MB，4.7 MB 实测可以），完整 MP4 用链接给。图片代理原样转发字节，不会再压缩。录屏打码后用 macOS Vision 逐帧识别文字复查
- **CDN**：防盗链关着（GitHub 图片代理才取得到）；每小时 4 GB 的流量上限和费用跟 SpeakMore 共用，SpeakMore 的下载统计按它自己的文件名认，不会算进 Snug
- **证书**：`dl.zephyrxiang.com` 的免费证书 2027-01-12 到期，续期记在 SpeakMore 的记忆里；不换，两个项目的下载会一起断
- 上传用的是主账号密钥，以后可换成只能写 `snug/` 前缀的子账号密钥（未做）

相关：[[project-release]]
