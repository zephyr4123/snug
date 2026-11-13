# 开发

## 构建与发布

构建、测试、打包与发布统一由 `scripts/snug` 完成（`scripts/snug help` 查看全部命令）。

| 命令 | 作用 |
| :--- | :--- |
| `scripts/snug check` | 构建全部产物并运行全部测试（Swift Testing），任一步骤失败即以非零状态退出 |
| `scripts/snug app` | 生成 `build/Snug.app`（通用二进制）并签名 |
| `scripts/snug install` | 生成 App、安装至「应用程序」并打开；正在运行的 Snug 会先正常退出，窗口先行归位 |
| `scripts/snug dist` | 生成可分发的 `dist/<版本>/Snug-<版本>.dmg`：Developer ID 签名，App 与 dmg 分别公证并装订票据 |
| `scripts/snug ship` | 发布：前置检查 → check → dist → 创建 GitHub Release 草稿并上传 → 校验下载地址 → 公开 |

**环境要求**：Xcode 与 Swift 6。

**签名**：钥匙串中有唯一一张「Developer ID Application」证书时自动使用；否则采用 ad-hoc 签名，此时每次重新构建后都需要重新授权辅助功能。

**发布流程**

1. 修改并提交仓库根目录的 `VERSION`（版本号只记录在这里）
2. 打上带说明的同名标签并推送：`git tag -a v2.0.0 -m "…"`。Release 的说明取自标签说明
3. 执行 `scripts/snug ship`

- 已发布的版本不再更改：GitHub 上已公开、而本机的安装包与之不同时，发布会被拒绝，需提升版本号
- `ship` 中断后可直接重新执行，`dist/<版本>/` 中出自同一提交的安装包会被复用

**本机配置**存放在不纳入版本控制的 `.machine.env`（模板为 `.machine.env.example`），只记录名称，不存放密钥：

| 键 | 含义 |
| :--- | :--- |
| `MAC_SIGNING_IDENTITY` | 签名证书；`-` 表示 ad-hoc |
| `MAC_NOTARY_PROFILE` | `xcrun notarytool store-credentials` 存储的公证档案名 |
| `GH_CONFIG_DIR` / `GITHUB_ACCOUNT` | 发布所用的 GitHub 账号 |

## 代码结构

代码分为三层，依赖单向向下：

| 目标 | 内容 |
| :--- | :--- |
| `SnugCore` | 纯逻辑：连接判定与会话、手机屏调度 `PhoneDesk`、手势翻译 `TouchTranslator`、规格、还原记录、配置、日志、启动参数。系统能力抽象为协议，测试中使用假实现 |
| `SnugSystem` | 系统层：`CGVirtualDisplay` 建屏与撤屏、辅助进程切换 2 倍模式、辅助功能接口移动窗口、按进程发送字号快捷键、手势事件监听 |
| `Snug` | 应用层：UU远程 感知、AppController、手机屏上的窗口列表与指示条、设置、欢迎页、菜单栏 |

## 启动参数

参数有误时会打印用法。

| 参数 | 作用 |
| :--- | :--- |
| `--render-<界面> <目录>` | 将界面渲染为 PNG：`settings` / `welcome` / `about` / `legacy` / `phone`（不启动监控，不改动屏幕） |
| `--preview-phone` | 正常启动，但不等待手机连接即创建手机屏，无需手机即可查看屏上的列表（**会真实创建一块屏幕**） |
| `--dump-uu` | 打印从 UU远程 读取到的控制端与当前屏幕 |
| `--set-mode <屏幕编号> <宽> <高>` | 辅助进程模式：将指定屏幕切换至 2 倍后立即退出（供主程序内部调用） |

## 数据与日志

| 位置 | 内容 |
| :--- | :--- |
| `~/Library/Application Support/Snug/config.json` | 设置 |
| `~/Library/Application Support/Snug/phone-screen.json` | 手机屏上窗口的还原记录 |
| `~/Library/Application Support/Snug/zoom.json` | 各 App 记忆的字号级数 |
| `~/Library/Logs/Snug.log` | 日志 |

实现细节见 [工作原理](how-it-works.md)。
