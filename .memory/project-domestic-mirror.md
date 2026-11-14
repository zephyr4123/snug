---
name: project-domestic-mirror
description: 国内源 dl.zephyrxiang.com/snug/（腾讯云 COS + CDN，与 SpeakMore 共用桶、按 snug/ 隔离）放安装包和 README 媒体；README 图片经 GitHub 代理有大小上限；证书 2027-01-12 到期
metadata:
  node_type: memory
  type: project
  originSessionId: f97709de-705a-489b-bb7a-7353b1fba51c
  modified: 2026-11-14T12:01:10.683Z
---

2026-11-13 主人定的：安装包要有国内源（以后官网也从这里取，GitHub Release 照留）；README 的图片、视频也放这里，用原画质。

- **摆法**：前缀 `https://dl.zephyrxiang.com/snug/`，和 SpeakMore 发布包同一个桶（桶名、地域、凭据名在不进 git 的 `.machine.env`，这份记忆会公开，别写进来）。`v<版本>/` 发过不改；`latest/Snug.dmg` 是固定的最新版地址，缓存 5 分钟、只往新版本换；`media/<名>.<指纹>.<后缀>` 放 README 媒体
- **命令**：`ship` 发版时自动传；`mirror <版本>` 补传 GitHub 上已公开的版本；`media <文件…>` 传媒体并打出地址。对象都带 sha256 元数据，重跑一样就跳过、不一样就拒绝
- **README 媒体**：GitHub 会删掉 `<video>`，录屏在 README 里用 animated WebP，完整 MP4 用链接给（链接不走代理，没有大小限制）。README 里的外链图片一律经 GitHub 图片代理转发，大小上限在代理而不在 COS：开源 camo 默认 5 MiB，4.97 MB 实测能取到，更大的没试过。代理原样转发字节，不会再压缩
- **动图体积**：几乎全花在整屏滚动的帧上（每帧约 50 KB，打字、弹键盘的帧约 7 KB）；超了先用 img2webp 逐帧 `-q` 只降滚动段，宽度 540 在 README 30% 宽下看不出差别
- **录屏打码**：按字符范围定位（Vision `boundingBox(for:)`），只糊「用户名@机器名」那一截，敲的命令照常露出；逐帧识别复查，并拿没打码的原画做正对照，证明识别在该尺寸下认得出来
- **CDN**：防盗链关着（GitHub 图片代理才取得到）；每小时 4 GB 的流量上限和费用跟 SpeakMore 共用，SpeakMore 的下载统计按它自己的文件名认，不会算进 Snug
- **看下载量**（主人问了才查）：GitHub 用 releases API 的 download_count，含少量发版核对、扣不干净；国内源没有现成命令，先在 SpeakMore 仓库跑一次它的 stats 刷新 `.stats/logs` 里同域名的访问日志缓存（只读），再筛 `/snug/`，按「字节 ÷ 包大小」折算、同 IP 同天最多算 1 次、本机出口算自测。curl 拉包的不能当自测：2026-11-14 宣传片后十几个不同来源用 curl 下载，还去找 `latest/` 下的校验文件，多半是用户让 AI 助手装的
- **证书**：`dl.zephyrxiang.com` 的免费证书 2027-01-12 到期，续期记在 SpeakMore 的记忆里；不换，两个项目的下载会一起断
- 上传用的是主账号密钥，以后可换成只能写 `snug/` 前缀的子账号密钥（未做）

相关：[[project-release]]
