# 开发

## 构建与发布

构建、测试、打包与发布统一由 `scripts/snug` 完成（`scripts/snug help` 查看全部命令）。

| 命令 | 作用 |
| :--- | :--- |
| `scripts/snug check` | 构建全部产物并运行全部测试（Swift Testing），任一步骤失败即以非零状态退出 |
| `scripts/snug app` | 生成 `build/Snug.app`（通用二进制）并签名 |
| `scripts/snug install` | 生成 App、安装至「应用程序」并打开；正在运行的 Snug 会先正常退出，窗口先行归位 |
| `scripts/snug dist` | 生成可分发的 `dist/<版本>/Snug-<版本>.dmg`：Developer ID 签名，App 与 dmg 分别公证并装订票据；再将公证后的 App 打成应用内更新用的 `Snug-<版本>.pack` |
| `scripts/snug ship` | 发布：前置检查 → check → dist → 生成 `update.json` → 创建 GitHub Release 草稿并上传 → 公开 → 上传国内源 → 两处均从下载地址核对 |
| `scripts/snug mirror <版本>` | 将 GitHub 上已公开的版本补传至国内源：安装包从 GitHub 下载，校验一致后上传；有应用内更新文件的版本一并补传 |
| `scripts/snug media <文件…>` | 将 README 使用的图片与视频上传至国内源并输出地址；视频仅重新封装（不重新编码），并去除录制时间、地点等元数据 |

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

## 应用内更新

每个版本只多发布两个文件，GitHub Release 与国内源各一份，内容相同：

- `Snug-<版本>.pack`：将 App 按内容切块（FastCDC，平均 128 KiB），去重后逐块 LZMA 压缩，首尾相接
- `update.json`：版本号、2.1.0 以来各版本的更新日志，以及清单（每块在包中的位置、每个文件由哪几块组成）

App 将本机已安装的 Snug 按同样方式切块，只按字节范围从最新的包中读取本机缺少的块，因此从任何旧版本都能直接升到最新版，无需逐版本的补丁。格式与打包逻辑位于 `SnugCore/Update`，发布工具 `snug-release`（`Sources/SnugRelease`）与 App 共用同一份实现：`dist` 时打包，并照清单拼装、核对签名，通过后才交出；`ship` 时生成 `update.json`。

## 代码结构

代码分为三层，依赖单向向下：

| 目标 | 内容 |
| :--- | :--- |
| `SnugCore` | 纯逻辑：连接判定与会话、手机屏调度 `PhoneDesk`、屏幕适配 `ScreenFit`、手势翻译 `TouchTranslator`、规格、还原记录、配置、日志、启动参数、更新包格式。系统能力抽象为协议，测试中使用假实现 |
| `SnugSystem` | 系统层：`CGVirtualDisplay` 建屏与撤屏、辅助进程切换分辨率档位、辅助功能接口移动窗口、按进程发送字号快捷键、手势事件监听 |
| `Snug` | 应用层：UU远程 感知、AppController、应用内更新 `Updater`、手机屏上的窗口列表与指示条、设置、关于、欢迎页、菜单栏 |

发布工具 `SnugRelease` 只依赖 `SnugCore`，由 `scripts/snug` 调用。

## 启动参数

参数有误时会打印用法。

| 参数 | 作用 |
| :--- | :--- |
| `--render-<界面> <目录>` | 将界面渲染为 PNG：`settings` / `welcome` / `about` / `legacy` / `phone` / `update`（不启动监控，不改动屏幕） |
| `--preview-phone` | 正常启动，但不等待手机连接即创建手机屏，无需手机即可查看屏上的列表（**会真实创建一块屏幕**） |
| `--dump-uu` | 打印从 UU远程 读取到的表格行、控制端与当前屏幕 |
| `--set-mode <屏幕编号> <宽>` | 辅助进程模式：将手机屏切换至该宽度一档的 2 倍模式后立即退出（供主程序内部调用） |

## 数据与日志

| 位置 | 内容 |
| :--- | :--- |
| `~/Library/Application Support/Snug/config.json` | 设置 |
| `~/Library/Application Support/Snug/phone-screen.json` | 手机屏上窗口的还原记录 |
| `~/Library/Application Support/Snug/zoom.json` | 各 App 记忆的字号级数 |
| `~/Library/Logs/Snug.log` | 日志 |

实现细节见 [工作原理](how-it-works.md)。
