# UU远程 适配

UU远程 的适配器，接入方式见 [接入新的远控](README.md)，核心怎么判定连接见 [工作原理](../how-it-works.md#连接判定)。

| 位置 | 内容 |
| :--- | :--- |
| `Sources/Remotes/UU/Logic`（`RemoteUU`） | 身份 `UURemote`、三路信号 `UUSignals`、控制端表格 `ControllerTable`、推流日志 `CaptureLogParser` 与 `CaptureSessionState`、进程 `UUProcessWatch`、自检判定 `UUCheck` |
| `Sources/Remotes/UU/System`（`RemoteUUSystem`） | 适配器 `UURemoteAdapter`、读界面 `UUAccessibility` 与 `ControllerReader`、盯推流日志 `CaptureLogWatcher`、进程与覆盖窗口 `UURemoteApp`、诊断 `UUDump` 与 `UUCheckRun` |
| `Tests/Remotes/UU`（`RemoteUUTests`） | 以上纯逻辑的测试，推流日志夹具 `Fixtures/` |

## 身份

| 项 | 值 |
| :--- | :--- |
| 日志名 | `UU`（日志写「检测到 UU 连入」，命令行写 `uu`） |
| 界面名 | UU远程 |
| 自家 App | `com.netease.uuremote`，不出现在 App 资源库里 |
| 注入事件的进程 | `UURemoteServer`：被远程时注入鼠标键盘、推流、放覆盖窗口，手势翻译只接管它发来的 |

## 三路信号

| 信号 | 来源 |
| :--- | :--- |
| 覆盖窗口 | UU远程 在被控期间显示的窗口 |
| 控制端表格 | 通过辅助功能接口读取 UU远程 主窗口中「本机被控中」的列表，得到控制端名称 |
| 推流事件 | 系统日志中 UURemoteServer 的屏幕捕获开始与停止，以及所推的屏 |

- **在场**：任一路给出正面证据即在场（覆盖窗口在屏、认出控制端、推流进行中）
- **控制端表格只作在场证据**：UU远程 仅在被控期间显示控制端列表，没有「无人控制」的界面。读不到控制端（例如主窗口停留在首页、错误页）不代表远程已经结束（#1）
- **只认本机被控页**：只读取与「本机被控中」标题位于同一层级的那张列表。在 UU远程 中点开同账号的另一台设备时，设备详情页里也有一张格式相同的列表，列出的是正在控制那台设备的人；同一账号的两台 Mac，手机连接其中一台时，另一台若停留在它的详情页，曾被误判为本机被控而加上手机屏（#12）。左侧栏的「本机被控中」卡片在本机被控期间一直存在，因此仅凭窗口中出现这几个字不足以判断
- **切屏**：UU 可能先开新抓屏流再停旧流。Snug 用同一进程内的抓屏对象地址配对开始和停止，最后一路停下后才进入停流宽限。
- **推流屏**：推流开始前日志会描述所推的屏，取它作为推流屏；没在推流时为空
- **中途启动**：监听开始时先回看最近 4 小时的推流日志，只认此刻的 UURemoteServer 进程打的，远程进行中启动 Snug 也能正确识别
- **信号快照**：`overlay=是 控制端=iPhone capture=是`，写进连入、断开日志；自检按同一写法读回（`UUSignals.logged`），往返测试钉住两边

## 兼容自检

UU远程 更新后，先用手机照常连一次（切到 Snug 的屏），再运行 `scripts/snug remote-check uu`。

- **核对项**：UU远程 版本（对照上次核对的版本）；后台进程 `UURemoteServer`；抓屏与编码框架（ScreenCaptureKit、VideoToolbox）是否仍被链接；推流日志能否认出推流的开始、停止与所推的屏；Snug 连入时推流信号是否亮起；能否认出控制端
- **判定**：位于 `RemoteUU` 的 `UUCheck`，推流日志按正式运行的解析与状态回放，Snug 日志的摘要位于 `SnugCore/Remote/SnugLogDigest`，只摘归 UU 的远程（别家的远程、控制端不算）。只核对此刻的 `UURemoteServer` 进程：UU远程 更新即换进程，更新前的远程不计入。远程过、Snug 日志里却认不出一次 UU 连入，或连入的信号快照读不出，报「需留意」（多半是日志写法改了）
- **取证材料**：`~/Library/Logs/Snug-uu-check/`，每次覆盖：报告、UU 推流日志、上一次远程前后 `UURemoteServer` 的全部日志、该时段的 Snug 日志、UU 界面树、链接情况与当前屏幕
- **核对完成**：报告无问题且手机实测无误后，将 `UUCheck.verifiedVersion` 改为新版本
- **范围**：只读日志与界面，不操作 UU远程；触控、新连接先推主屏需手机实测，暂未纳入

## 留在共用代码里的 UU 实测值

以下按 UU远程 实测标定，在核心、系统层或 App 层，各家共用，不进适配接口：建屏早于知道是哪家远控来连，或者已有通用机制兜住。接别家时实测，不同再改并补测试。

- 屏幕比例的让位：手机竖屏上下各 91 点、横屏左右 82+72 点（`ScreenFit`）
- 平板屏右上角让开 50 点，UU 的圆形菜单按钮压着约 45 点（`TouchStyle`、设计令牌 `tabletTopRightClear`）
- 新连接从主屏开始推流（设为主屏常驻的依据，`ScreenPlan`）
- 断开防抖 1.5 秒、自扰静默期 5 秒（`ConnectionTracker`）
- 手势只接管鼠标左键（`TouchEvents`）
- 换比例后要在远控里切走再切回（屏上提示「屏幕比例已调整」）
