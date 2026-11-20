<div align="center">

**简体中文** · [English](README.en.md) · [日本語](README.ja.md)

<img src="Assets/AppIcon/AppIcon-1024.png" width="128" alt="Snug 图标">

# Snug

**Make UU Remote Native on Any Device**

为 UU远程 打造 · 远程 Mac 的显示与触控增强<br>每台设备专属屏幕 · 原生触屏手势 · App 资源库

[![最新版本](https://img.shields.io/github/v/release/zephyr4123/snug?label=%E6%9C%80%E6%96%B0%E7%89%88%E6%9C%AC&color=blue)](https://github.com/zephyr4123/snug/releases/latest) ![Apple Silicon · Intel](https://img.shields.io/badge/Apple%20Silicon%20%C2%B7%20Intel-%E9%80%9A%E7%94%A8-success) ![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue) ![已公证](https://img.shields.io/badge/Apple-%E5%B7%B2%E5%85%AC%E8%AF%81-black?logo=apple) [![许可证 MIT](https://img.shields.io/badge/%E8%AE%B8%E5%8F%AF%E8%AF%81-MIT-green)](LICENSE)

[下载](#-下载) · [原生体验](#-每台设备原生体验) · [多设备](#-一台-mac所有设备) · [App 资源库](#-app-资源库) · [截图](#-截图) · [对比](#-与其他方案的对比) · [安装](#-安装) · [使用](#-使用方式) · [限制](#-已知限制) · [开发](#-开发)

<br>

<img src="https://dl.zephyrxiang.com/snug/media/hero-architecture.0ee41447.png" width="92%" alt="原理图：Snug 在 Mac 上为手机、平板、电脑分别建立屏幕，经 UU远程 推送至各设备并铺满画面">
<p><sub>▶ <a href="https://dl.zephyrxiang.com/snug/media/phone-demo.a97e46d1.mp4">观看高清演示视频</a></sub></p>

</div>

> [!IMPORTANT]
> **致 UU远程 VIP 用户**：UU远程 自 2026 年 12 月 1 日起将多屏、虚拟屏等功能纳入 VIP。Snug 基于虚拟屏架构，若你恰为 UU远程 VIP 用户，欢迎一试。
>
> **立场**：Snug 为独立社区项目，与 UU远程 无商业关联。是否开通 VIP，请依自身对 UU远程 的需求决定，不必为 Snug 专门开通。目前专注 UU远程，暂不自行适配其他远控软件；对接部分已抽为可替换的适配层，欢迎提 PR 接入或 fork 自行适配，详见[开发](#-开发)。

> 承接自 [aoyamashou/UUyc-companion](https://github.com/aoyamashou/UUyc-companion)（UU远程伴侣，作者 AoyamaShou，MIT 许可），完整保留原作者的版权声明与提交历史。2.0 起以手机屏为核心重新设计，2.6 起扩展至平板与电脑。

## 📥 下载

<img src="Assets/AppIcon/AppIcon-1024.png" width="88" align="left" alt="Snug 图标">

**Snug for macOS** [![最新版本](https://img.shields.io/github/v/release/zephyr4123/snug?label=%E6%9C%80%E6%96%B0%E7%89%88%E6%9C%AC&color=blue)](https://github.com/zephyr4123/snug/releases/latest)<br>通用安装包，支持 Apple 芯片与 Intel，适用于 macOS 14 及更新版本<br>已签名并经 Apple 公证，拖入「应用程序」即可使用

<br clear="left">

| 渠道 | 说明 | 下载 |
| :--- | :--- | :--- |
| **国内源** | 腾讯云 CDN 加速，中国大陆推荐 | [Snug.dmg](https://dl.zephyrxiang.com/snug/latest/Snug.dmg) |
| **GitHub Releases** | 附更新说明、校验文件与历史版本 | [前往下载](https://github.com/zephyr4123/snug/releases/latest) |

两个渠道的安装包完全相同。Snug 仅需安装于被控 Mac，控制端只需 UU远程。

> Windows 被控端：参见 [社区移植](#-社区移植)。

## ✨ 每台设备，原生体验

UU远程 将桌面整体等比缩放至控制端，比例不符即留黑边，文字与控件随之缩小。Snug 为每台控制端新增一块比例匹配的屏幕：手机、平板按移动端尺度铺满，适配触屏操作；电脑与本机分辨率一致，全屏无黑边。

### 手机：竖屏 · 横屏

<p align="center"><img src="https://dl.zephyrxiang.com/snug/media/compare-uu-original.cf4158d1.png" width="36%" alt="UU远程 原版：整块桌面缩小显示于手机屏幕"> <img src="https://dl.zephyrxiang.com/snug/media/phone-claude-code.93e21d9d.png" width="36%" alt="Snug：窗口铺满全屏，字号放大"><br><sub>同一内容 · 左：UU远程 原版 · 右：Snug</sub></p>

- **竖屏、横屏**：按机型计算比例，避让 UU远程 工具栏，2 倍 HiDPI；横屏适合代码、终端与宽幅页面
- **窗口铺满**：所选窗口独占全屏
- **字号放大**：Ghostty、终端、iTerm2、VS Code、Cursor、Zed 自动放大，按 App 分别记忆

<p align="center"><img src="https://dl.zephyrxiang.com/snug/media/phone-landscape-web.a1670af8.png" width="72%" alt="iPhone 横屏：网页完整呈现，右侧为 UU远程 工具栏"><br><sub>横屏：宽幅页面完整呈现</sub></p>

### 原生手势

UU远程 移动端沿用触控板的手势逻辑；Snug 在手机屏与平板屏上按触屏习惯重新映射。

| 触屏操作 | UU远程 原版 | Snug |
| :--- | :--- | :--- |
| 单指滑动 | 鼠标拖拽，易误选文字 | 页面滚动，松手保留惯性 |
| Codex 向右 / 向左横滑 | 鼠标拖拽 | 展开 / 关闭侧边栏 |
| 长按后拖动 | 鼠标拖拽 | 拖选文字 |
| 长按松开 | 普通点击 | 右键菜单 |

<p align="center"><img src="https://dl.zephyrxiang.com/snug/media/phone-demo.2cee4e81.webp" width="30%" alt="实机演示：打开窗口、弹出键盘输入命令、恢复会话、单指滚动、返回列表"> <img src="https://dl.zephyrxiang.com/snug/media/phone-context-menu.997dd70f.png" width="30%" alt="长按调出右键菜单"><br><sub>单指滚动 · 长按调出右键菜单</sub></p>

- 仅作用于手机屏与平板屏，其他屏幕及本机触控板、鼠标不受影响

### 平板：铺满 · 原生手势

平板远程 Mac 以往多需外接键盘与触控板；Snug 平板屏按机型铺满，触控即用。

- **横屏、竖屏**：按机型计算比例，全屏铺满
- **原生手势**：同手机屏，滚动、右键、拖选均由触控完成，无需外接触控板
- **字号适中**：基准略大于平板原生，适合长时间使用
- **左右两栏**：横屏时 App 资源库分为 App 与窗口两栏，参见 [App 资源库](#-app-资源库)

<p align="center"><img src="https://dl.zephyrxiang.com/snug/media/ipad-landscape-vscode.7524622f.png" width="56%" alt="iPad 横屏：VS Code 铺满全屏，字号放大"> <img src="https://dl.zephyrxiang.com/snug/media/ipad-portrait-safari.22fa3ccc.png" width="27%" alt="iPad 竖屏：Safari 铺满全屏"><br><sub>iPad · 横屏 · 竖屏</sub></p>

### 电脑：铺满 · 无黑边

Snug 电脑屏按控制端分辨率建立，画面与本机一致。

> 电脑远程去黑边源自 Snug 的前身 [UUyc-companion](https://github.com/aoyamashou/UUyc-companion)（UU远程伴侣，作者 AoyamaShou）。Snug 沿用这一能力，改为新增屏幕：原有屏幕保持不变，主屏默认不变。

<p align="center"><img src="https://dl.zephyrxiang.com/snug/media/macbook-uu-original.4c593493.png" width="46%" alt="MacBook Air 上的 UU远程 原版：4K 屏画面上下留黑边，文字缩小"> <img src="https://dl.zephyrxiang.com/snug/media/macbook-snug.32bf15ab.png" width="46%" alt="MacBook Air 上的 Snug 电脑屏：同一窗口铺满，文字与本机一致"><br><sub>同一窗口 · 左：UU远程 原版 · 右：Snug 电脑屏</sub></p>

- **分辨率一致**：内置 Mac 全系默认分辨率与常见电脑分辨率，适用于 Windows 电脑；支持自定义，参见 [自定义屏幕](#自定义屏幕)
- **像素级对应**：带刘海的 MacBook 避让顶部区域，画面不缩放
- **保留电脑操作**：不转换手势，不放大字号，鼠标与触控板保持原样
- **设为主屏**（可选，默认不启用）：每次连接直接进入此屏，菜单栏、程序坞与原主屏窗口随之迁入，工作无缝接续，参见 [设为主屏](#设为主屏)
- **App 资源库**：从菜单栏打开，将其他屏幕的窗口移至此屏，支持一键还原，参见 [App 资源库](#-app-资源库)

## 🧩 一台 Mac，所有设备

### 自定义屏幕

每块屏幕的设备、型号、方向与名字均可自定义，最多 4 块，分别开关。

| 项目 | 说明 |
| :--- | :--- |
| 设备 | 手机、平板或电脑；比例与屏上功能随类别而定，见下表 |
| 型号 | 机型库选择，或填写分辨率、比例（如 1080×2400、9×20）；更换即时生效，无需重连 |
| 方向 | 竖屏或横屏，添加时选定 |
| 名字 | 显示于 UU远程 屏幕列表，便于识别 |

<p align="center"><img src="https://dl.zephyrxiang.com/snug/media/settings-add-screen.eed74389.png" width="46%" alt="添加屏幕：选定设备、方向、型号与名字"><br><sub>添加屏幕：设备 · 方向 · 型号 · 名字</sub></p>

| 屏幕 | 比例与尺寸 | 屏上功能 |
| :--- | :--- | :--- |
| 手机 · 竖 / 横 | 按机型计算，避让 UU远程 工具栏 | App 资源库、指示条、原生手势、字号放大 |
| 平板 · 横 / 竖 | 按机型计算，字号略大于原生 | 同上；横屏为左右两栏 |
| 电脑 · 横 | 与控制端分辨率一致；带刘海的 MacBook 避让顶部，像素级对应 | 无附加内容，等同普通显示器 |

- **一机两向**：同一台手机或平板，竖屏、横屏各设一块（屏幕详情中一键添加另一方向），转向时在 UU远程 中切换
- **多机轮换**：多台手机或平板各设一块，分别选定型号
- **跨设备**：手机、平板、电脑各设一块，换用设备时选择对应屏幕

### 屏幕列表

设置「屏幕」页集中管理全部屏幕；远程时，在 UU远程 屏幕列表中选择所需屏幕。

<p align="center"><img src="https://dl.zephyrxiang.com/snug/media/settings-screens-remote.4475b8da.png" width="43%" alt="Snug 设置「屏幕」页：远程中的屏幕列表与设为主屏"> <img src="https://dl.zephyrxiang.com/snug/media/uu-screen-list.a161e201.png" width="46%" alt="UU远程 屏幕菜单：四块 Snug 屏幕"><br><sub>左：Snug 设置中的屏幕列表 · 右：远程时 UU远程 中的屏幕列表</sub></p>

- **按需开关**：暂不使用的屏幕可关闭，关闭后远程时不再建立
- **设为主屏**（可选，默认不启用）：任一 Snug 屏幕均可设为主屏，常驻并在每次连接时直接进入，参见 [设为主屏](#设为主屏)
- **无显示器的 Mac mini、Mac Studio**：Snug 屏幕取代系统默认屏幕，远程即获得按控制端分辨率建立的完整桌面
- **机型库**：内置 19 个品牌的 785 款手机与 46 款平板（iPhone 8 及后续全系 iPhone，华为、小米、OPPO、vivo、三星等主流安卓机型，折叠屏内外屏分列），另含 13 款 Mac 与 9 种常见电脑分辨率

<p align="center"><img src="https://dl.zephyrxiang.com/snug/media/phone-models.391e818d.png" width="36%" alt="型号页：当前机型、自定义分辨率与按品牌排列的机型"><br><sub>型号：按品牌排列，支持自定义分辨率</sub></p>

### 设为主屏

可选，默认不启用；位于设置「屏幕」页底部。所选屏幕常驻并作为 Mac 的主屏，UU远程 每次连接即进入此屏，菜单栏、程序坞与原主屏窗口一并迁入。

- **为何常驻**：UU远程 在建立连接的时刻选定主屏，此后不随主屏变化切换。Snug 不接入 UU远程 的接口，仅能依据其在本机留下的窗口与推流日志察觉连接，察觉时画面已开始推送。所选屏幕须在连接前即已存在并作为主屏，这是现有条件下的唯一方式
- **影响**：程序坞、新开的窗口、系统提示与锁屏登录框均显示于此屏，本机不可见；远程时锁屏，可在控制端解锁。适用于未接显示器或以远程为主的 Mac，开启前需确认
- **取消**：设置中改回「不改」；菜单栏「取消设为主屏」；手机屏、平板屏 App 资源库右上角「取消主屏」。回到 Mac 本机使用前请先取消；Mac 已锁屏时，远程连接后在此屏取消
- **远程结束**：此屏及屏上的窗口原样保留，下次连接接续使用；取消设为主屏或退出 Snug 后，窗口归位，主屏与排布自动还原

## 🗂 App 资源库

手机屏与平板屏的首页，在移动端管理 Mac 上的 App：查找、打开、切换、新建、关闭与退出，无需回到电脑前。电脑屏的 App 资源库从菜单栏打开。

- **运行中**：每个运行中的 App 一张卡片，窗口列于其下；窗口无论位于哪块屏幕、哪个桌面空间，全屏或最小化，均可在此找到
- **全部**：本机全部 App 的图标网格，按名称排序；轻点未运行的 App 即打开
- **搜索**：匹配 App 名称与窗口标题，支持中文、英文、拼音全拼与首字母，如「bwl」对应「备忘录」

<p align="center"><img src="https://dl.zephyrxiang.com/snug/media/phone-app-library.865fc506.png" width="30%" alt="运行中：手机屏上窗口所属的 App 置于最上方"> <img src="https://dl.zephyrxiang.com/snug/media/phone-all-apps.7d4ada60.png" width="30%" alt="全部：本机全部 App 的图标网格"> <img src="https://dl.zephyrxiang.com/snug/media/phone-search.d365e194.png" width="30%" alt="搜索：输入 bwl 找到备忘录"><br><sub>运行中 · 全部 · 拼音首字母搜索</sub></p>

- **左右两栏**：横屏手机与平板上，左栏为 App，右栏为所选 App 的窗口

<p align="center"><img src="https://dl.zephyrxiang.com/snug/media/phone-landscape-library.30220d6f.png" width="54%" alt="iPhone 横屏：App 资源库左栏为 App，右栏为所选 App 的窗口"> <img src="https://dl.zephyrxiang.com/snug/media/ipad-landscape-library.b0f8b829.png" width="39%" alt="iPad 横屏：App 资源库左栏为 App，右栏为所选 App 的窗口"><br><sub>左右两栏 · 横屏手机 · 平板</sub></p>

- **电脑屏**：无资源库面板，从菜单栏打开 App 资源库窗口；标注每个窗口所在屏幕（含全屏窗口），一键移至此屏，移入的窗口一键还原。远端无法看到其他屏幕、无法拖动窗口时，以此移入与还原

<p align="center"><img src="https://dl.zephyrxiang.com/snug/media/mac-library.796eed17.png" width="60%" alt="电脑屏 App 资源库：标注窗口所在屏幕，一键移至此屏，移入的窗口一键还原"><br><sub>电脑屏：从菜单栏打开 App 资源库</sub></p>

| 操作 | 方式 |
| :--- | :--- |
| 打开窗口 | 轻点窗口，即铺满全屏；轻点 App，打开其最近使用的窗口 |
| 新建窗口 | 轻点 App 卡片上的「新建窗口」，新窗口按屏宽打开 |
| 关闭窗口 | 轻点窗口右侧的关闭按钮，再次轻点确认 |
| 退出 App | 轻点 App 卡片上的「退出」，再次轻点确认；10 秒未退出时可强制退出 |
| 存储未保存内容 | 关闭或退出时的「是否存储」对话框显示于当前屏幕，可在移动端直接选择 |
| 退出这块屏 | 轻点右上角「退出这块屏」并确认：窗口归位、屏幕移除，本次远程不再显示，下次远程恢复（断开后 15 秒内重连仍视为本次） |
| 取消主屏 | 设为主屏的屏幕上，轻点右上角「取消主屏」并确认：主屏改回 Mac，远程结束后移除此屏 |

### 与 iPhone 一致的操作

| iPhone | Snug 手机屏、平板屏 |
| :--- | :--- |
| App 资源库 | 首页：查找、打开与管理 Mac 上的 App |
| 主屏幕指示条 | 底部指示条，返回 App 资源库 |
| 左上角「‹ 返回」 | 左上角「‹ App 名」，返回当前窗口 |

### 适配任意 App

Snug 呈现的是 Mac 上的原生窗口，适用于任意 App，不绑定特定 AI：终端中的 Claude Code、ChatGPT 桌面版中的 Codex，体验与电脑前一致。

部分 App 设有最小宽度，无法缩至屏宽。Snug 先按屏宽铺开窗口；App 无法再缩窄时，将屏幕切换至恰好容纳的分辨率，再次铺满。

- 任何窗口均完整显示，不截断
- 等比缩放，不变形，点按位置准确
- 此类窗口文字略小，可在移动端双指放大

<p align="center"><img src="https://dl.zephyrxiang.com/snug/media/phone-chatgpt.a28ef053.png" width="36%" alt="ChatGPT 桌面版中的 Codex 铺满 Snug 手机屏"> <img src="https://dl.zephyrxiang.com/snug/media/phone-fit-settings.4e526ad6.png" width="36%" alt="设有最小宽度的系统设置完整铺满手机屏"><br><sub>左：ChatGPT 桌面版中的 Codex（文件链接已打码）· 右：设有最小宽度的系统设置，仍完整铺满</sub></p>

## 📸 截图

适用于手机屏与平板屏。在设置「触控」页开启「截图」后，底部指示条左侧显示相机键；轻点即截取铺满屏幕的窗口并存入 Mac 剪贴板，可粘贴至任意 App。截取内容为窗口原画，不受远程画质压缩影响。

- **裁剪**：截图后左下角显示缩略图，轻点进入裁剪；默认全选，拖动四角或四边收窄选区，轻点「完成」以选区替换剪贴板中的截图
- **权限**：需另行授予「录屏与系统录音」权限（macOS 14 为「屏幕录制」）：在设置「通用」页点按「授权…」，按系统提示重新打开 Snug 后生效；与辅助功能权限相互独立
- **默认关闭**：关闭时指示条不显示相机键，亦无需录屏权限

<p align="center"><img src="https://dl.zephyrxiang.com/snug/media/phone-screenshot-thumbnail.3dfb4e94.png" width="30%" alt="截图后左下角显示缩略图"> <img src="https://dl.zephyrxiang.com/snug/media/phone-screenshot-crop.0bd33902.png" width="30%" alt="裁剪：拖动四角或四边收窄选区"><br><sub>左：截图后显示缩略图 · 右：轻点进入裁剪</sub></p>

## 🆚 与其他方案的对比

| 方案 | 局限 | Snug |
| :--- | :--- | :--- |
| **AI 助手的远程控制** | 仅限自家 AI 的会话 | 适用于任意终端与 App，参见 [适配任意 App](#适配任意-app) |
| **UU远程 自带终端** | 独立于本机终端，断开后进程仍驻留 | 直接使用 Mac 现有的终端窗口 |
| **显示器欺骗器、虚拟屏工具** | 单一比例，换设备即留黑边；无触屏手势与窗口管理 | 每台设备专属屏幕；手机、平板配原生手势与 App 资源库 |

- **AI 助手的远程控制**：如 Claude Remote Control、ChatGPT 中的 Codex，均绑定单一产品
- **UU远程 自带终端**：运行于 UU远程 自身的 tmux，无法接续电脑上进行中的工作（如终端中的 Claude Code）

## 📦 安装

> **系统要求**：被控端 macOS 14 及更新版本，已安装 [UU远程](https://uuyc.163.com/)；控制端为任意安装 UU远程 的手机、平板或电脑。

**下载安装（推荐）**

1. 从「[下载](#-下载)」一节获取安装包（中国大陆推荐国内源）
2. 将 Snug 拖入「应用程序」并打开
3. 按欢迎页提示授予辅助功能权限（macOS 27 起名为「设备控制和数据访问」）

此后 Snug 常驻菜单栏，无需额外操作；再次打开 Snug 即显示设置。

**更新**：启动时自动检查，一键更新，保留设置与授权；亦可在设置「通用」页手动检查或切换更新源。2.1.0 之前的版本需手动下载替换。

<div align="center">
<img src="https://dl.zephyrxiang.com/snug/media/welcome.d538a8c3.png" width="30%" alt="欢迎页：用法与辅助功能授权"> <img src="https://dl.zephyrxiang.com/snug/media/settings-screens.694e6c80.png" width="30%" alt="设置「屏幕」页：屏幕列表与设为主屏"> <img src="https://dl.zephyrxiang.com/snug/media/settings-general.4e8bfc2c.png" width="30%" alt="设置「通用」页：开机启动、权限与软件更新">
<p><sub>欢迎页 · 设置：屏幕 · 设置：通用</sub></p>
</div>

**从源码构建**（需要 Xcode 与 Swift 6）

```bash
git clone https://github.com/zephyr4123/snug.git
cd snug && scripts/snug install
```

<details>
<summary>从「UU远程伴侣」迁移</summary>

两者同时运行会相互干扰，Snug 启动时提示退出旧版。若曾在旧版中启用守护助手，请另行执行：

```bash
launchctl bootout gui/$(id -u)/com.corndog.uudisplay.watchdog-agent
rm ~/Library/LaunchAgents/com.corndog.uudisplay.watchdog-agent.plist
```

</details>

## 🧭 使用方式

1. **添加屏幕**（按需）：默认仅一块竖屏「Snug 手机屏」；平板、电脑或横屏手机，在设置「屏幕」页添加并选定型号
2. **切换屏幕**：连接后，在 UU远程 屏幕列表中选择对应屏幕
3. **选择 App 或窗口**：手机屏、平板屏上，在 App 资源库中轻点 App 或窗口，即铺满全屏；电脑屏从菜单栏打开 App 资源库
4. **切换窗口**：轻点底部指示条返回 App 资源库；另选窗口时，原窗口自动归位
5. **结束远程**：窗口归位、字号复原，Snug 屏幕随之移除；设为主屏的屏幕及其上的窗口保留

> 💡 建议将 UU远程 画质调至最高：画质较低时画面模糊，平板上尤为明显。

## 🔒 隔离与还原

- **仅改动 Snug 屏幕**：不关闭任何屏幕，不改动其他窗口；未切换至 Snug 屏幕时，UU远程 与原版一致。主屏默认不变；启用「设为主屏」后，所选屏幕常驻为主屏，取消或退出 Snug 后自动还原
- **撤屏前清场**：在 Snug 屏幕上直接打开的窗口，撤屏前移至主屏，不被挤至角落
- **先记录，后改动**：预先记录窗口原始位置与字号，Snug 意外退出后亦可还原
- **窗口直接关闭亦可还原**：在移动端直接关闭的窗口，App 下次以 Snug 屏幕尺寸打开时，自动归位并复原字号
- **无响应时保持原状**：App 暂无响应时不强行移动窗口，并在屏上说明原因
- **不收集数据**：除检查更新外不连接任何服务器，不收集任何数据；截图仅存入本机剪贴板，不留存

## 🚧 已知限制

| 限制 | 说明 |
| :--- | :--- |
| 依赖 macOS 未公开接口 | 系统大版本更新后可能失效 |
| UU远程 一次仅允许一台设备控制 | 多块屏幕轮换使用，不支持多台设备同时远程 |
| UU远程 每次连接从主屏开始 | 需在屏幕列表中手动选择一次；设为主屏后，每次连接直接进入该屏，参见 [设为主屏](#设为主屏) |
| UU远程 Mac 端最多列出 5 块屏幕 | 含 Mac 自身屏幕；以 Mac 远程时，可先关闭暂不使用的 Snug 屏幕 |
| 屏幕不随设备自动横竖切换 | 横竖兼用时各设一块，转向时在 UU远程 中切换 |
| 非网易官方软件 | 与 UU远程 及其开发商无关；UU远程 更新后部分功能可能受影响 |
| 远程结束后 Snug 屏幕偶尔未移除 | 推流停止未被系统日志记录时出现，菜单栏仍显示「远程中」；在设置中关闭已开启的屏幕即可还原 |
| VS Code、Cursor 窗口在移动端以快捷键或菜单关闭后，字号可能被保留 | 远程结束后重新打开时若字号偏大，按 ⌘- 复原（关闭时屏上提示级数）；开启手势时轻点窗口关闭按钮，或在 App 资源库中关闭，则不受影响 |
| 未接显示器的 Mac 无法切回原屏幕 | macOS 仅在无任何显示器时提供默认屏幕，Snug 屏幕出现后即撤下；在 App 资源库右上角退出这块屏，或在设置中关闭，即恢复原画面 |

各项限制的成因见 [工作原理](docs/how-it-works.md#已知限制的技术原因)。

## 🔧 开发

```bash
scripts/snug check     # 构建并运行全部测试
scripts/snug install   # 构建、安装并打开
```

- 代码分三层：`SnugCore`（纯逻辑）→ `SnugSystem`（系统接口）→ `Snug`（界面）；对接 UU远程 的部分是可替换的远控适配层（`Sources/Remotes`）
- 打包、发布、启动参数与数据位置：[开发文档](docs/development.md)
- 连接判定、窗口移动与手势翻译：[工作原理](docs/how-it-works.md)

**接入其他远控**：架构已调整就绪，核心不依赖任何一家远控，接一家新的只加它自己的适配器。欢迎提 PR 接入，或 fork 后自行接入：[接入新的远控](docs/remotes/README.md) · [设计记录](docs/remote-adapter/README.md)

## 🧹 卸载

1. 在菜单栏退出 Snug（窗口先行还原）
2. 将「应用程序」中的 Snug 移至废纸篓
3. 可选：删除设置与日志 `rm -rf ~/Library/Application\ Support/Snug ~/Library/Logs/Snug.log*`
4. 可选：在系统设置「辅助功能」中移除 Snug；开启过截图的，一并在「录屏与系统录音」中移除

## 🌐 社区移植

| 平台 | 项目 | 维护者 | 说明 |
| :--- | :--- | :--- | :--- |
| Windows x64 | [Snug for Windows](https://github.com/rizetngan/snug-for-windows) | [rizetngan](https://github.com/rizetngan) | 基于 Snug 2.5.0 移植，C# / .NET 10 / WPF；已发布正式版 |
| Windows 10 / 11 | [snug-win](https://github.com/nicocart/snug-win) | [nicocart](https://github.com/nicocart) | 基于 Snug 2.5.0 移植，C# / .NET 8 / WPF |

社区移植由各自作者独立开发、发布与维护。本仓库仅开发与测试 macOS 版，未测试上述移植版本；使用问题请至对应仓库反馈。

## 🙏 致谢

首先，谨向 **[UU远程](https://uuyc.163.com/)** 致以诚挚的敬意。

- **品质卓越**：连接稳定，响应灵敏，画质与帧率均可按需调节。远程控制涉及编码、传输与跨网络连接等诸多工程环节，能够达到日常工作可长期依赖的水准，其技术门槛不言而喻。
- **三年免费**：技术壁垒如此之高的产品，上线三年始终向所有用户免费开放，堪称对整个远程生态的慷慨馈赠。正是这份开放，使社区得以在其基础上持续探索，远程伴侣、单指滚动、虚拟屏幕等方案相继涌现，Snug 亦由此而生。
- **支持商业化**：优秀的产品理应获得回报。UU远程 推出增值服务，我们由衷赞成，作者亦已第一时间开通 VIP。

谨此致谢。

亦感谢以下项目与贡献者：

- [UUyc-companion](https://github.com/aoyamashou/UUyc-companion)（MIT）：AoyamaShou，Snug 的前身
- [Better Remote](https://github.com/pincc-debug/better-remote)（MIT）：pincc-debug，为 UU远程 实现单指滚动的思路
- [PermissionFlow](https://github.com/jaywcjlove/PermissionFlow)（MIT）：小弟调调，授权引导与拖拽授权面板
- [FreeDisplay](https://github.com/huberdf/FreeDisplay)（MIT）：huberdf，`CGVirtualDisplay` 接口声明
- 社区 PR 作者：bubble、gencheng liu、Rongzheng Liu（#10，全屏桌面空间下读取 UU远程 窗口）；yupeng（#26，跨屏窗口经主屏中转）；李小双（#30、#36，断线后立即结束远程、撤屏前与断线等待期内移开指针）；LI Long（#31，多屏窗口归位与菜单栏定位的排查）；11ze（#39，降低后台扫描与辅助功能读取开销）；eltociear（#40，日文版 README）
- 虚拟屏的实现参考了 [DeskPad](https://github.com/Stengo/DeskPad)、[Side Screen](https://github.com/tranvuongquocdat/SideScreen) 与 Chromium 的相关代码

## ⭐ Star 趋势

<p align="center"><a href="https://www.star-history.com/#zephyr4123/snug&Date"><picture><source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=zephyr4123/snug&type=Date&theme=dark"><source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=zephyr4123/snug&type=Date"><img src="https://api.star-history.com/svg?repos=zephyr4123/snug&type=Date" width="80%" alt="Snug 的 GitHub Star 数随时间的变化"></picture></a></p>

## 📄 许可证

[MIT](LICENSE) © 2026 AoyamaShou，© 2026 zephyr4123
