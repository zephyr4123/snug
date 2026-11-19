# 开发

## 构建与发布

构建、测试、打包与发布统一由 `scripts/snug` 完成（`scripts/snug help` 查看全部命令）。

| 命令 | 作用 |
| :--- | :--- |
| `scripts/snug check` | 构建全部产物并运行全部测试（Swift Testing，以及 `scripts/` 中的 Python 单测），任一步骤失败即以非零状态退出 |
| `scripts/snug app` | 生成 `build/Snug.app`（通用二进制）并签名 |
| `scripts/snug install` | 生成 App、安装至「应用程序」并打开；正在运行的 Snug 会先正常退出，窗口先行归位 |
| `scripts/snug dist` | 生成可分发的 `dist/<版本>/Snug-<版本>.dmg`：Developer ID 签名，App 与 dmg 分别公证并装订票据；再将公证后的 App 打成应用内更新用的 `Snug-<版本>.pack` |
| `scripts/snug ship` | 发布：前置检查 → check → dist → 生成 `update.json` → 创建 GitHub Release 草稿并上传 → 公开 → 上传国内源 → 两处均从下载地址核对 |
| `scripts/snug mirror <版本>` | 将 GitHub 上已公开的版本补传至国内源：安装包从 GitHub 下载，校验一致后上传；有应用内更新文件的版本一并补传 |
| `scripts/snug media <文件…>` | 将 README 使用的图片与视频上传至国内源并输出地址；视频仅重新封装（不重新编码），并去除录制时间、地点等元数据 |
| `scripts/snug uu-check [小时]` | UU远程 兼容自检（只读）：核对 Snug 依赖 UU远程 的几处，回看最近几小时（默认 4）的日志并输出报告；见下文「UU远程 兼容自检」 |
| `scripts/snug stats` | 统计安装包下载量（只读）：GitHub Release 与国内源分别计算后相加，扣除自测；口径见下文「国内源」中的「下载量」 |

**环境要求**：Xcode 与 Swift 6。

**签名**：钥匙串中有唯一一张「Developer ID Application」证书时自动使用；否则采用 ad-hoc 签名，此时每次重新构建后都需要重新授权辅助功能。

**发布流程**

1. 修改并提交仓库根目录的 `VERSION`（版本号只记录在这里）
2. 打上带说明的同名标签并推送：`git tag -a v2.0.0 -m "…"`。Release 的说明与 App 内的更新日志都取自标签说明：第一行去掉「Snug <版本>：」后作为标题；正文中的「安装」一节只出现在 Release 上
3. 执行 `scripts/snug ship`

- 已发布的版本不再更改：GitHub 上已公开、而本机的安装包与之不同时，发布会被拒绝，需提升版本号
- `ship` 中断后可直接重新执行，`dist/<版本>/` 中出自同一提交的安装包会被复用；国内源上已有且内容一致的文件会跳过

**本机配置**存放在不纳入版本控制的 `.machine.env`（模板为 `.machine.env.example`），只记录名称，不存放密钥：

| 键 | 含义 |
| :--- | :--- |
| `MAC_SIGNING_IDENTITY` | 签名证书；`-` 表示 ad-hoc |
| `MAC_NOTARY_PROFILE` | `xcrun notarytool store-credentials` 存储的公证档案名 |
| `GH_CONFIG_DIR` / `GITHUB_ACCOUNT` | 发布所用的 GitHub 账号 |
| `COS_BUCKET` / `COS_REGION` | 国内源所在的 COS 桶与地域 |
| `COS_CREDENTIAL` / `COS_SECRETS_LOADER` | 腾讯云密钥的凭据名与按需加载器（提供 `withkey`）；环境中已有 `TENCENTCLOUD_SECRET_ID` / `TENCENTCLOUD_SECRET_KEY` 时可留空 |
| `SPEAKMORE_STATS` | SpeakMore 仓库中的 `.stats` 目录（含 `logs/` 与 `self-ips.json`），`stats` 从中读取国内源的访问日志 |

## 国内源

安装包与 README 媒体同时发布到腾讯云 COS，经 CDN 分发，地址前缀为 `https://dl.zephyrxiang.com/snug/`。桶为私有，仅允许 CDN 读取。

| 路径 | 内容 | 缓存 |
| :--- | :--- | :--- |
| `v<版本>/Snug-<版本>.dmg`、`.sha256` | 各版本安装包，发布后不再更改 | 一年 |
| `v<版本>/Snug-<版本>.pack`、`update.json` | 应用内更新所用的分块包及其说明（见下文「应用内更新」） | 一年 |
| `latest/Snug.dmg` | 固定的最新版下载地址（README 与官网使用），只向更新的版本切换，下载文件名带版本号 | 5 分钟 |
| `latest/update.json` | App 启动时检查的地址，只向更新的版本切换 | 5 分钟 |
| `media/<名称>.<指纹>.<后缀>` | README 的图片与视频，内容变化时地址随之变化 | 一年 |

- 每个对象记录 sha256：重复上传时内容一致即跳过，不一致即拒绝
- 上传使用的 Python 环境位于仓库内的 `.venv`（不纳入版本控制），依赖版本锁定在 `scripts/cos-requirements.txt`，缺失时自动安装
- GitHub 的 README 不播放外链视频：README 中的动态演示使用动图，完整视频以链接形式提供

**下载量**（`scripts/snug stats`，计算位于 `scripts/download_stats.py`，单测随 `check` 运行）

- GitHub Release：只计 `.dmg`。`update.json`（App 检查更新）、`.sha256` 与 `.pack` 的下载数单独列出，不计入；每个版本扣除一次 `ship` 从下载地址的核对
- 国内源：读取 CDN 访问日志，按「传输字节 ÷ 安装包大小」折算为完整下载次数，同一 IP 同一天最多计一次；`latest/Snug.dmg` 按当时最新的版本折算
- 国内源与 SpeakMore 共用 CDN 域名，访问日志由 SpeakMore 的 `stats` 拉取并缓存，本命令只读该缓存、不使用密钥；日志超过 6 小时未更新时会提示先刷新
- 自测来源：SpeakMore 记录的本机出口，以及用 curl 拉取版本目录下 `update.json` 或 `.pack` 的来源（仅 `ship` / `mirror` 核对时如此）。用 curl 拉取 `media/` 或安装包的来源不视为自测：Linux 上的 curl、读取 README 的 AI 工具、替用户安装的 AI 助手都会这样请求

## 应用内更新

每个版本只多发布两个文件，GitHub Release 与国内源各一份，内容相同：

- `Snug-<版本>.pack`：将 App 按内容切块（FastCDC，平均 128 KiB），去重后逐块 LZMA 压缩，首尾相接
- `update.json`：版本号、2.1.0 以来各版本的更新日志，以及清单（每块在包中的位置、每个文件由哪几块组成）

App 将本机已安装的 Snug 按同样方式切块，只按字节范围从最新的包中读取本机缺少的块，因此从任何旧版本都能直接升到最新版，无需逐版本的补丁。格式与打包逻辑位于 `SnugCore/Update`，发布工具 `snug-release`（`Sources/SnugRelease`）与 App 共用同一份实现：`dist` 时打包，并照清单拼装、核对签名，通过后才交出；`ship` 时生成 `update.json`。

## UU远程 兼容自检

UU远程 更新后，先用手机照常连一次（切到 Snug 的屏），再运行 `scripts/snug uu-check`，数秒内输出报告。

- **核对项**：UU远程 版本（对照上次核对的版本）；后台进程 `UURemoteServer`；抓屏与编码框架（ScreenCaptureKit、VideoToolbox）是否仍被链接；推流日志能否认出推流的开始、停止与所推的屏；Snug 连入时推流信号是否亮起；能否认出控制端
- **判定**：❌ 问题 · ⚠️ 需留意 · ✅ 正常 · ℹ️ 待下次核对；有问题时以非零状态退出。判定位于 `SnugCore/Diagnostics/UUCheck`，推流日志按正式运行的解析与状态回放，Snug 日志的摘要位于 `SnugLogDigest`。只核对此刻的 `UURemoteServer` 进程：UU远程 更新即换进程，更新前的远程不计入
- **取证材料**：`~/Library/Logs/Snug-uu-check/`，每次覆盖：报告、UU 推流日志、上一次远程前后 `UURemoteServer` 的全部日志、该时段的 Snug 日志、UU 界面树、链接情况与当前屏幕
- **核对完成**：报告无问题且手机实测无误后，将 `UUCheck.verifiedVersion` 改为新版本
- **范围**：只读日志与界面，不操作 UU远程；触控、新连接先推主屏需手机实测，暂未纳入

## 代码结构

代码分为三层，依赖单向向下：

| 目标 | 内容 |
| :--- | :--- |
| `SnugCore` | 纯逻辑：连接判定与会话、屏幕调度（见下）、屏幕适配 `ScreenFit`、机型库 `DeviceCatalog`、手势翻译 `TouchTranslator`、截图 `Screenshots`、还原记录、配置、日志、启动参数、更新包格式。系统能力抽象为协议，测试中使用假实现 |
| `SnugSystem` | 系统层：`CGVirtualDisplay` 建屏与撤屏、辅助进程切换分辨率档位、设主屏与还原排列 `DisplayArrangementService`、辅助功能接口移动窗口、按进程发送字号快捷键、手势事件监听 `TouchTap`、ScreenCaptureKit 截图 |
| `Snug` | 应用层：UU远程 感知、AppController、应用内更新 `Updater`、Snug 屏上的 App 资源库（`Screens/`）、指示条与截图裁剪、设置（屏幕、触控、通用三页）、添加屏幕与屏幕详情、关于、电脑屏的 App 资源库窗口、欢迎页、菜单栏 |

发布工具 `SnugRelease` 只依赖 `SnugCore`，由 `scripts/snug` 调用。

`SnugCore` 的目录依赖单向：`Model`（屏的身份 `ScreenID`、设备的类别和数值等纯值类型）← `Config`、`Persistence` ← `Screens`。配置怎么翻成屏的身份和比例只在 `ScreenPlan` 写一处。

屏幕调度在 `SnugCore/Screens`，分四块，依赖单向：

| 类型 | 管什么 |
| :--- | :--- |
| `ScreenPlan` | 纯函数：按配置和远程状态算出这一刻要哪几块屏（`ScreenWish`；设为主屏的那块不在远程也要，即常驻），每块给什么行为（`ScreenBehavior.touch`：是不是触屏，即有没有面板、翻不翻译手势、铺不铺满、调不调字号）。行为只在这里按型号的类别定，下游只认它、不认类别；`Desk.State` 把它发布给界面 |
| `ScreenSet` | 屏幕拓扑的唯一来源：加屏、撤屏、换档、换比例、重试、最短在线时间、设为主屏与还原排列 |
| `Desk` | 一块屏上的事：放窗口（手机、平板铺满换档，电脑只挪过来居中）、换档、字号、归位、还原记录（触屏 `placed/<屏 id>.json`，电脑屏挪过来的窗口一个一份），正在做什么按号排（`Desk.Ticket`） |
| `DeskSet` | 管所有 `Desk`：在同一条 `SerialLane` 上排队，处理跨屏的事（窗口从一块屏转到另一块、退出 App 时各屏归位、撤屏前清场、在手机上退出某块屏）；留下的账交给 `LeftBehindLedger`，盯退出和关窗交给 `RequestWatcher` |

`AppController` 每次感知到变化就调 `ScreenPlan.wishes` 交给 `DeskSet.setWishes`，界面只读 `AppState.desks`（每块屏的状态）。

设计令牌：`design/design-tokens.json` 是界面数值的唯一来源。`Sources/Snug/UI/DesignTokens.swift`（`MacTokens`、`TouchTokens`、`MotionTokens`）由测试生成，不手改；`DesignTokensTests` 校验两边一致。改了令牌后重新生成：

```bash
SNUG_WRITE_TOKENS=1 swift test --filter DesignTokensTests
```

手势翻译分两半：`SnugCore/Touch` 是纯状态机，一次手势只认一块范围 `TouchRegion`（位置与缩放倍数），不依赖哪块屏；`SnugSystem` 中 `TouchTap` 负责监听线程，持有每块屏的范围，按下时按落点选定这次手势用哪一块，`TouchEvents` 负责读入与拼装事件。`AppController` 只决定范围：开着手势时，每块触屏（手机、平板屏）各一块范围，正在裁剪截图的那块除外。新增一种手势时，在状态机里加判定与 `TouchCommand`，在 `TouchEvents` 里拼装要补发的事件，再在 `TouchTap` 按命令分派处补上一支。

## 启动参数

参数有误时会打印用法。

| 参数 | 作用 |
| :--- | :--- |
| `--render-<界面> <目录>` | 将界面渲染为 PNG：`settings` / `welcome` / `about` / `legacy` / `menu` / `screens` / `library` / `update`（不启动监控，不改动屏幕）。`screens` 是 Snug 屏上的面板，覆盖手机竖横、平板竖横；`library` 是电脑屏的 App 资源库窗口 |
| `--preview-screens` | 正常启动，但不等待连接即创建屏幕列表中开着的屏，无需控制端即可查看屏上的列表（**会真实创建屏幕**；设了主屏的同样会设） |
| `--dump-uu` | 打印从 UU远程 读取到的界面（文字、表格与行）、认出的控制端与当前屏幕 |
| `--check-uu [小时]` | UU远程 兼容自检（`scripts/snug uu-check` 调用）：输出报告，原始材料写入 `~/Library/Logs/Snug-uu-check/`；有问题时以非零状态退出 |
| `--probe-screens <规格…>` | 实测用（多屏的 V1～V12，结论见记忆 project-multi-screen）：每份规格建一块实验屏，打印各档模式与 2 倍是否可用，按 Ctrl-C 撤屏并还原排布。规格是逗号分隔的 `键=值`：`modes=宽x高+…`（必填）、`name`、`serial`（默认用 999000001 起的实验身份）、`cap=像素宽x像素高`、`pattern=on\|off`（校准图）、`main=on`（设为主屏，最多一块）。**会真实创建屏幕**，测试时随测随撤，免得指针跑到看不见的屏上 |
| `--set-mode <屏幕编号> <宽> <高>` | 辅助进程模式：将一块 Snug 的屏切换至该档的 2 倍模式后立即退出（供主程序内部调用；高由主程序按型号的比例算好传入） |
| `--restore-mode <屏幕编号> <模式编号> <宽> <高> <像素宽> <像素高> <刷新率> session\|permanent` | 辅助进程模式：将一块屏幕设回该模式后立即退出，只对当前登录生效或连同永久配置（供主程序内部调用：创建、移除 Snug 的屏时被系统改变模式的屏幕） |

## 数据与日志

| 位置 | 内容 |
| :--- | :--- |
| `~/Library/Application Support/Snug/config.json` | 设置，含屏幕列表 `screens`、主屏 `mainScreen`。兼容 2.5 的 `phoneScreen`、`phone` 取第一块竖屏手机，也支持沿用原先那块已识别为 iPad 的竖屏。旧字段过两个大版本再停写。降级后，2.5 写盘时会丢掉 `screens`、`mainScreen`、`nextSerialBlock`，再升级只保留旧字段记录的那块屏 |
| `~/Library/Application Support/Snug/placed/<屏 id>.json` | 各块屏上窗口的还原记录；电脑屏挪过来的窗口一个一份，`placed/<屏 id>~<pid>-<窗口号>.json`。2.5 的 `phone-screen.json` 启动时挪成 `placed/phone.json` 再按它还原；手机屏已经有账时挪成 `placed/phone-2.5.json`，一样还 |
| `~/Library/Application Support/Snug/zoom.json` | 各 App 记忆的字号级数 |
| `~/Library/Application Support/Snug/left-behind.json` | 在 Snug 之外关闭的窗口待还原的位置与字号（保留两周） |
| `~/Library/Logs/Snug.log` | 日志 |

实现细节见 [工作原理](how-it-works.md)。
