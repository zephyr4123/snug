<div align="center">

<img src="Assets/AppIcon/AppIcon-1024.png" width="128" alt="Snug 图标">

# Snug

**让 Mac 在手机上拥有原生级的操作体验**

为 UU远程 打造的移动端工作区<br>独立竖屏 · 窗口铺满 · 字号放大 · iOS 手势

[![最新版本](https://img.shields.io/github/v/release/zephyr4123/snug?label=%E6%9C%80%E6%96%B0%E7%89%88%E6%9C%AC&color=blue)](https://github.com/zephyr4123/snug/releases/latest) ![Apple Silicon · Intel](https://img.shields.io/badge/Apple%20Silicon%20%C2%B7%20Intel-%E9%80%9A%E7%94%A8-success) ![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue) ![已公证](https://img.shields.io/badge/Apple-%E5%B7%B2%E5%85%AC%E8%AF%81-black?logo=apple) [![许可证 MIT](https://img.shields.io/badge/%E8%AE%B8%E5%8F%AF%E8%AF%81-MIT-green)](LICENSE)

[下载](#-下载) · [核心体验](#-核心体验) · [交互](#-与-iphone-一致的交互) · [对比](#-与其他方案的对比) · [安装](#-安装) · [使用](#-使用方式) · [限制](#-已知限制) · [开发](#-开发)

<br>

<img src="https://dl.zephyrxiang.com/snug/media/phone-window-list.7edc548b.png" width="30%" alt="窗口列表"> <img src="https://dl.zephyrxiang.com/snug/media/phone-demo.06d6f8d8.webp" width="30%" alt="实机演示：打开窗口、单指滚动、回到列表"> <img src="https://dl.zephyrxiang.com/snug/media/phone-context-menu.997dd70f.png" width="30%" alt="长按调出右键菜单">
<p><sub>窗口列表 · 实机演示 · 长按调出右键菜单</sub><br><sub>▶ <a href="https://dl.zephyrxiang.com/snug/media/phone-demo.f35c99a1.mp4">观看高清演示视频</a></sub></p>

</div>

> 承接自 [aoyamashou/UUyc-companion](https://github.com/aoyamashou/UUyc-companion)（UU远程伴侣，作者 AoyamaShou，MIT 许可），完整保留原作者的版权声明与提交历史。2.0 起围绕「手机屏」重新设计。

## 📥 下载

<img src="Assets/AppIcon/AppIcon-1024.png" width="88" align="left" alt="Snug 图标">

**Snug for macOS** [![最新版本](https://img.shields.io/github/v/release/zephyr4123/snug?label=%E6%9C%80%E6%96%B0%E7%89%88%E6%9C%AC&color=blue)](https://github.com/zephyr4123/snug/releases/latest)<br>一个安装包同时支持 Apple 芯片与 Intel，适用于 macOS 14 及更新版本<br>已签名并通过 Apple 公证，下载后拖入「应用程序」即可

<br clear="left">

| 渠道 | 说明 | 下载 |
| :--- | :--- | :--- |
| **国内源** | 腾讯云 CDN 加速，中国大陆推荐 | [Snug.dmg](https://dl.zephyrxiang.com/snug/latest/Snug.dmg) |
| **GitHub Releases** | 附更新说明、校验文件与历史版本 | [前往下载](https://github.com/zephyr4123/snug/releases/latest) |

两个渠道提供的是同一个安装包。

## ✨ 核心体验

UU远程 将整块桌面等比压缩进手机屏幕；Snug 为手机增加一块专属竖屏，让 Mac 的窗口以手机的尺度呈现。

<p align="center"><img src="https://dl.zephyrxiang.com/snug/media/compare-uu-original.cf4158d1.png" width="36%" alt="UU远程 原版：整块桌面缩在手机屏幕里"> <img src="https://dl.zephyrxiang.com/snug/media/phone-claude-code.93e21d9d.png" width="36%" alt="搭配 Snug：窗口铺满整屏，字号放大"><br><sub>同一段内容 · 左：UU远程 原版 · 右：搭配 Snug</sub></p>

| | UU远程 原版 | 搭配 Snug |
| :--- | :--- | :--- |
| **画面** | 整块桌面等比缩小，文字与控件随之缩小数倍 | 专属竖屏，窗口铺满整屏 |
| **字号** | 随画面一同缩小 | 终端与编辑器自动放大 |
| **单指滑动** | 识别为鼠标拖拽 | 页面滚动，带惯性 |
| **切换窗口** | 在缩小的桌面中查找 | 窗口列表，轻点即开 |

- 远程结束后，窗口自动归位、字号复原
- 不切换至手机屏时，UU远程 与原版完全一致

## 📱 与 iPhone 一致的交互

| iPhone | Snug 手机屏 |
| :--- | :--- |
| 多任务界面 | 窗口列表，汇集 Mac 上的全部窗口 |
| 打开 App | 选中窗口，独占整屏 |
| 主屏幕指示条 | 底部指示条，返回窗口列表 |
| 左上角「‹ 返回」 | 左上角「‹ App 名」，返回当前窗口 |
| 动态字体 | 字号随屏放大，按 App 分别记忆 |

### 手势：为触屏重新设计

UU远程 手机端沿用触控板的手势逻辑；Snug 在手机屏上按手机的使用习惯重新解释。

| 手机上的操作 | UU远程 原版 | Snug 手机屏 |
| :--- | :--- | :--- |
| 单指滑动 | 鼠标拖拽，容易误选文字 | 页面滚动，松手带惯性 |
| 长按后拖动 | 鼠标拖拽 | 拖选文字 |
| 长按松开 | 普通点击 | 调出右键菜单 |

- 仅在手机屏内生效；其他显示器与本机的触控板、鼠标不受影响

## 🆚 与其他方案的对比

| 方案 | 局限 | Snug |
| :--- | :--- | :--- |
| **AI 助手的远程控制** | 只能操作自家 AI 的会话 | 任意终端与 App 均可使用 |
| **UU远程 自带终端** | 独立于本机终端，断开后进程仍驻留 | 直接使用 Mac 原有的终端窗口 |
| **UU远程 原版手势** | 沿用触控板逻辑 | 为触屏重新设计，见 [手势](#手势为触屏重新设计) |

- **AI 助手的远程控制**：如 Claude Remote Control、ChatGPT 中的 Codex，均与单一产品绑定
- **UU远程 自带终端**：运行在 UU远程 自己的 tmux 中，与 Mac 上已打开的终端互不相通，电脑上进行中的工作（如终端里的 Claude Code）无法接续；断开远程后，会话与其中的进程仍在后台运行

**不绑定任何一家 AI**：Snug 放上手机屏的是 Mac 上的窗口本身，终端里的 Claude Code、桌面 App 里的 Codex 都能直接使用。

<p align="center"><img src="https://dl.zephyrxiang.com/snug/media/phone-claude-code.93e21d9d.png" width="36%" alt="终端里的 Claude Code 铺满 Snug 手机屏"> <img src="https://dl.zephyrxiang.com/snug/media/phone-chatgpt.a28ef053.png" width="36%" alt="ChatGPT 桌面版里的 Codex 铺满 Snug 手机屏"><br><sub>左：终端里的 Claude Code · 右：ChatGPT 桌面版里的 Codex（文件链接已打码）</sub></p>

## 📦 安装

> **系统要求**：macOS 14 或更新版本，被远程的 Mac 已安装 [UU远程](https://uuyc.163.com/)。手机端只需 UU远程。

**下载安装（推荐）**

1. 从「[下载](#-下载)」一节获取安装包（中国大陆推荐国内源）
2. 将 Snug 拖入「应用程序」并打开
3. 按欢迎页提示授予辅助功能权限（macOS 27 起名为「设备控制和数据访问」）

完成后 Snug 常驻菜单栏，此后无需任何操作。

<div align="center">
<img src="https://dl.zephyrxiang.com/snug/media/welcome.57ad51da.png" width="45%" alt="欢迎页"> <img src="https://dl.zephyrxiang.com/snug/media/settings-ready.482119c9.png" width="45%" alt="设置">
<p><sub>欢迎页 · 设置</sub></p>
</div>

**从源码构建**（需要 Xcode 与 Swift 6）

```bash
git clone https://github.com/zephyr4123/snug.git
cd snug && scripts/snug install
```

<details>
<summary>从「UU远程伴侣」迁移</summary>

两者同时运行会相互干扰，Snug 启动时会提示退出旧版。若在旧版中启用过守护助手，请再执行：

```bash
launchctl bootout gui/$(id -u)/com.corndog.uudisplay.watchdog-agent
rm ~/Library/LaunchAgents/com.corndog.uudisplay.watchdog-agent.plist
```

</details>

## 🧭 使用方式

1. **切换屏幕**：手机或平板连接后，在 UU远程 的屏幕列表中选择「Snug 手机屏」

   <img src="https://dl.zephyrxiang.com/snug/media/uu-screen-picker.212fdbe9.png" width="50%" alt="UU远程 的屏幕列表：显示屏 3（Snug 手机屏）">

2. **选择窗口**：轻点列表中的窗口，窗口即铺满整屏
3. **切换窗口**：轻点底部指示条返回列表；另选窗口时，原窗口自动归位
4. **结束远程**：窗口回到原位、字号复原，手机屏随之移除

## 🔒 隔离与还原

- **只改动手机屏**：不更改主显示器，不关闭任何屏幕，不触碰其他窗口
- **先记录，后改动**：窗口的原始位置与字号先行记录，Snug 意外退出后也能还原
- **无响应时保持原状**：App 暂时无响应时不强行移动窗口，并在屏上说明原因
- **不联网**：不连接任何服务器，不收集任何数据

## 🚧 已知限制

| 限制 | 说明 |
| :--- | :--- |
| 依赖 macOS 未公开接口 | 系统大版本更新后可能失效 |
| 屏幕比例以 iPhone 17 Pro Max 为准 | 其他机型可能有少量黑边；仅提供竖屏 |
| 部分窗口无法完全铺满 | 系统设置、Safari 等限定了最小宽度，窗口靠左放置 |
| 字号放大仅限终端与编辑器 | Ghostty、终端、iTerm2、VS Code、Cursor、Zed；浏览器不做调整 |
| 非网易官方软件 | 与 UU远程 及其开发商无关；UU远程 更新后部分功能可能受影响 |

各项限制的成因见 [工作原理](docs/how-it-works.md#已知限制的技术原因)。

## 🔧 开发

```bash
scripts/snug check     # 构建并运行全部测试
scripts/snug install   # 构建、安装并打开
```

- 代码分为三层：`SnugCore`（纯逻辑）→ `SnugSystem`（系统接口）→ `Snug`（界面）
- 打包、发布、启动参数与数据位置：[开发文档](docs/development.md)
- 连接判定、窗口移动与手势翻译：[工作原理](docs/how-it-works.md)

## 🧹 卸载

1. 在菜单栏中退出 Snug（窗口会先还原）
2. 将「应用程序」中的 Snug 移到废纸篓
3. 可选：删除设置与日志 `rm -rf ~/Library/Application\ Support/Snug ~/Library/Logs/Snug.log*`
4. 可选：在系统设置的「辅助功能」中移除 Snug

## 🙏 致谢

首先感谢 **[UU远程](https://uuyc.163.com/)**。它提供了稳定、流畅的远程控制，画质与帧率可以自由调节，而且完全免费。正因为有这样一款免费且高质量的产品，社区才能在它之上继续完善远程体验，Snug 也由此而来。谨致敬意。

同样感谢以下项目与贡献者：

- [UUyc-companion](https://github.com/aoyamashou/UUyc-companion)（MIT）：AoyamaShou，Snug 的前身
- [Better Remote](https://github.com/pincc-debug/better-remote)（MIT）：pincc-debug，为 UU远程 实现单指滚动的思路
- [PermissionFlow](https://github.com/jaywcjlove/PermissionFlow)（MIT）：小弟调调，授权引导与拖拽授权面板
- [FreeDisplay](https://github.com/huberdf/FreeDisplay)（MIT）：huberdf，`CGVirtualDisplay` 接口声明
- 社区 PR 作者：bubble、gencheng liu、Rongzheng Liu（#10，全屏桌面空间下读取 UU远程 窗口）
- 虚拟屏的实现参考了 [DeskPad](https://github.com/Stengo/DeskPad)、[Side Screen](https://github.com/tranvuongquocdat/SideScreen) 与 Chromium 的相关代码

## 📄 许可证

[MIT](LICENSE) © 2026 AoyamaShou，© 2026 zephyr4123
