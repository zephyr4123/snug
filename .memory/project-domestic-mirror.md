---
name: project-domestic-mirror
description: 国内源 dl.zephyrxiang.com/snug/（腾讯云 COS + CDN，和 SpeakMore 共用桶、按 snug/ 隔离）：安装包、README 图片视频都放这；GitHub README 不播外链视频；证书 2027-01-12 到期
metadata:
  node_type: memory
  type: project
  originSessionId: f97709de-705a-489b-bb7a-7353b1fba51c
  modified: 2026-11-13T13:07:25.650Z
---

2026-11-13 主人定的：README 的图片、视频和安装包都走自己的腾讯云 COS + CDN，「通过路径名字隔离」，不用压得像马赛克的图；安装包要有国内源（以后官网的下载也从这取），GitHub Release 照留。

**Why:** 国内下 GitHub 慢；图和视频放 COS 不受仓库体积限制，可以用原画质。

**How to apply:**
- 地址前缀 `https://dl.zephyrxiang.com/snug/`，桶和 SpeakMore 发布包同一个（桶名、地域、凭据名在不进 git 的 .machine.env；这份记忆会公开，别写进来）。摆法：`v<版本>/`（发过不改）、`latest/Snug.dmg`（固定最新版地址，缓存 5 分钟，只往新版本换）、`media/<名>.<指纹>.<后缀>`（README 媒体）。
- 只走 `scripts/snug`：`ship` 发版时自动传国内源；`mirror <版本>` 补传 GitHub 上已公开的版本（v2.0.0 在 11-13 这样补的）；`media <文件…>` 传 README 媒体并打出地址。每个对象带 sha256 元数据，重跑一样就跳过、不一样就拒绝。
- GitHub README 会删掉 `<video>` 标签（11-13 用渲染接口实测），录屏在 README 里用动图（animated WebP 画质远好于 GIF），完整 MP4 放 COS 用链接给；官网可以直接播 MP4。GitHub 图片代理（camo）原样转发 CDN 的字节，不再压缩（实测校验值一致）。
- CDN 防盗链关着（camo 才取得到）；全球加速、跟随源站缓存头。每小时 4 GB 的流量封顶和费用跟 SpeakMore 共用；SpeakMore 的下载统计按它自己的文件名认，不会把 Snug 算进去。
- `dl.zephyrxiang.com` 的免费证书 2027-01-12 到期，续期记在 SpeakMore 的记忆里（reverse-anything 仓库）；到期不换，两个项目的下载一起断。
- 上传用的是主人现有的腾讯云凭据；以后可换成只能写这个桶 `snug/` 前缀的子账号密钥（未做）。
- 下一步：主人拍完真机截图和录屏后，README 的图全部换成国内源地址（docs/images 里的渲染图到时一并处理）。

相关：[[feedback-release-cli]]、[[project-release-identity]]
