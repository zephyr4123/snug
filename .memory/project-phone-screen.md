---
name: project-phone-screen
description: 实测坑（代码注释和 docs 没写的）：UU 更新先跑 remote-check uu；UU 推流与恢复模式的规律、看推哪块屏；系统按「这组屏幕」记模式；真机自测只从访达重开正式版；ColorSync；资源库与关窗的 App 实测
metadata:
  node_type: memory
  type: project
  originSessionId: f97709de-705a-489b-bb7a-7353b1fba51c
  modified: 2026-11-24T13:30:00.000Z
---

**UU 更新后先跑 `scripts/snug remote-check uu`**：几秒出报告，原始材料在 `~/Library/Logs/Snug-uu-check/`，核对项见 docs/remotes/uu.md「兼容自检」，核对完改 `UUCheck.verifiedVersion`。

大部分实测结论已在代码注释、`docs/how-it-works.md`、`docs/remotes/uu.md` 里（事件形态、两路推流、换比例要切走再切回、控制端表、2 倍门槛、互换窗口等），改代码前先读注释，别回退。这里只留仓库里没有的。

**UU**
- 新连接一律从连上那一刻的主屏开始，不记上次选的屏、不跟指针（11-16 多次实测），所以「默认进某块屏」只能靠设主屏常驻
- 停推流时 UURemoteServer 按推流开始时拍下的模式逐块恢复（`SLSCompleteDisplayConfigurationWithOption: kCGSConfigureForSession`），手机屏会被拨回旧档，Snug 复查 1.5 秒内切回；用 `.permanently` 切也一样，别再试。逆向 4.46.0：连接开始、开始采集、切屏时按分辨率改模式，原始模式只拍一次
- 看 UU 推哪块屏：`/usr/bin/log show --info --debug` 筛 UURemoteServer 的 `SCDisplay initWithDict:`、`CaptureWithCompletionHandler:]`、`addStreamOutput:type:`、`SCStream dealloc]`，按行里的流地址把开、停、释放对上；开流前列一遍屏、紧跟那行是这路要推的。登记了 type=1 的那路是声音流（挂主屏、推到远程结束），在推的屏看最近开推的那路画面。切屏顺序不固定：本机先停旧画面再开新的，#56 先开新的再停旧的（11-24 查清，推流表 CaptureStreams 照此判断）。zsh 的 `log` 是内建命令，写全路径
- 推流时长上限 2.0.1 已删（误判两次、救场零次），别加回来；推流卡住在推流表取证（CaptureStreams），不靠控制端表反推

**系统按「这组屏幕」记模式**（#13）：WindowServer 给每组屏各记一份模式，组合一变就套用并写进永久配置（`/Library/Preferences/com.apple.windowserver.displays.plist`）。机制和修法见 how-it-works「不影响其他屏幕」
- 显示器睡着时释放的虚拟屏要等唤醒才下线（可能拖几小时），睡着时改模式会失败
- 只用 `.forSession` 设回，磁盘上那组仍是旧值、下次登录又回去；用 `.permanently` 提交一个和当前相同的模式就会写进永久配置（实测）
- 镜像组里的从属屏不单独管（PR #43，2.7.4）：`Screens.standalone()`；本机只有内建屏，镜像没实测，等作者在 2.7.4 上验证撤屏后
- 睡着时撤屏、唤醒后设回只有单测：锁屏下按 Snug 的按钮不可靠。要测就写个直接调 ScreenSet 的小程序，别靠界面按钮

**悬停提示残留（#46，11-21，未复现、等报告人补材料）**：报告人（Mac mini + 两块外接屏 + BetterDisplay）说程序坞标签、Snug 菜单栏提示「等待连接」挂着不消失，退出 Snug 就好。本机实验（草稿区 `tooltip/` 的小程序，按窗口列表探测提示窗）：普通 App 的提示在挪窗口、warp 走指针、加撤虚拟屏、虚拟屏上悬停后撤屏、挪外接屏这几种情况下都会自己收掉；挪外接屏时指针不动、内容平移，会在指针下冒出新提示（已证实）。程序坞标签、菜单栏提示由系统画，没测成。主人定：太小众，先请报告人补完整日志、截图、关手势是否还出现。实验要点：测试 App 不在前台时提示不出（要 activate，测完把原前台 App 还回去）；终端没录屏权限，截不了图；程序坞会被全屏 App 藏起来

**真机自测**
- **正式版只让访达开**：`osascript -e 'tell application "Finder" to open (POSIX file "/Applications/Snug.app" as alias)'`。别用 `open -a` 或直接执行：LaunchServices 会把发起者的环境变量交给 Snug，再传给从屏上打开的 App（11-15、11-16 两次把 `CLAUDE_CODE_*` 带进主人的 Ghostty）。查法 `ps -E -ww -o command= -p <pid> | tr ' ' '\n' | grep CLAUDE_CODE`
- 测试版：`scripts/snug app`，SIGTERM 正在跑的 Snug（`pkill` 锚定完整路径），用 `env -i HOME=… PATH=/usr/bin:/bin /usr/bin/open -n -g build/Snug.app --args --preview-screens` 起（权限按 Snug 自己算、没有环境变量可传）；屏幕列表直接写 config.json。测完 SIGTERM，再从访达重开正式版
- 测录屏等权限要从访达开测试版（从终端起会算在终端名下）；授权弹「退出并重新打开」时选「稍后」，否则重开的是「应用程序」里那份
- 手动打开会弹设置窗口，用辅助功能点 `first button of window "通用" whose subrole is "AXCloseButton"` 关掉
- 主人可能正在用这台 Mac：别抢焦点、别切主屏的桌面空间、别发全局键盘事件（用辅助功能设值或 `CGEvent.postToPid`）；锁屏时辅助功能读不到窗口，停手等主人
- 辅助功能的坑：SwiftUI 设置页开关 AXPress 没反应，要提窗口再点；面板窗口序号跟着焦点变，按横坐标选；手机屏 App 列表懒加载，可见区外的行位置是 (0,982) 0×0；`tell application "TextEdit"` 会卡在自动化授权，一律走 System Events；别点桌面墙纸（会触发「显示桌面」）；别把自己的终端窗口放上屏
- 辅助功能要关掉沙箱跑（沙箱里窗口全报成应用自己，和锁屏时一样）；菜单栏图标在应用的 AXExtrasMenuBar 下，AXPress 能弹出菜单。按进程发的合成鼠标、滚动事件（`CGEvent.postToPid`，带窗口号）进不了 Snug 的面板，锁不锁屏都一样（11-27），屏上要点就用辅助功能；全局事件会挪主人的光标
- 截不了屏（终端没录屏权限，关掉沙箱也不行）：界面用辅助功能读树（草稿区写个 `AXUIElementCopyAttributeValue` 递归打印的小程序），露没露、谁压谁用 `CGWindowListCopyWindowInfo(.optionOnScreenOnly)`（不要权限，按前后顺序）。全局键盘事件只在确认焦点在 Snug 的面板上、且主人说了不用电脑时发：焦点不在就会打进主人的 Ghostty（Esc 会打断会话），先把访达点到前台兜底
- **合成按键绝不带修饰键标志**：11-24 给 Ctrl+← 的按下、松开都设了 Control+Fn，系统一直当它们按着，之后的按键全成了 Ctrl+键，Fn 还唤起了主人常驻的 Typeless 语音输入。每个事件 `flags = []`，发前发后查 `CGEventSource.flagsState(.hidSystemState)`，卡住就发空 flagsChanged 松开并停手；切桌面这类操作别用合成按键
- 主人日常输入法是简体拼音（`SCIM.ITABC`）。拼音在不激活 Snug 的面板里照常能用，要按真实键码打（unicode 字符串绕过输入法）
- ~~在 Snug 之外进全屏、退全屏时 CGWindowList 一时读不到窗口~~ ⚠️更正（11-25，#63）：不是窗口真没了，是查法错了。`CGWindowListCopyWindowInfo(.optionIncludingWindow)` 只报此刻显示着的窗口，藏起来、最小化、App 被隐藏、进出全屏那 0.5 秒都报没有；`CGWindowListCreateDescriptionFromArray` 按编号查才报「在、未显示」，只有真关、App 重建窗口、App 被杀才查不到（测试窗口 2955 次采样一次不丢）。exists 已改，随 2.9.1 发布
- 点关闭只收起来的 App（orderOut，飞书、微信、企业微信）：系统给的辅助功能列表和远程令牌都找不到这个窗口，挪不动；最小化、App 被隐藏的找得到、挪得动。AppKit 窗口 orderOut 后之前拿到的辅助功能对象永久失效（再显示也不恢复），所以别靠留对象判死活
- 进出全屏的动画：约 0.5 秒窗口不属于任何桌面空间（`SLSCopySpacesForWindows` 为空）、不显示，末尾 10～50 毫秒的读数和 orderOut 完全一样（同一空间、没排在屏上、辅助功能列表里没有），单次读数分不清，只能隔过动画再看
- 窗口实验法（草稿区不持久，要用再写）：自己写个最小宽度 1060 的测试 App（Info.plist + swiftc，用分布式通知遥控 orderOut / 最小化 / 隐藏 / 重建）；后台启动、没激活过的 App 窗口不显示，起的时候激活一次、再把焦点还回去；实验屏用身份 999000001、切档照 Snug 用短命子进程。端到端：开发版 `--preview-screens`，资源库的行用辅助功能 AXPress，底部小横条是图片，只能按坐标点（点前查修饰键）
- 系统按「这组屏幕」记每个窗口的位置和大小，换排布时套回来，没放上屏的窗口也可能被改大小（11-18）
- 每个新身份第一次上线多一份 ICC，测完列给主人清

**ColorSync**：每块屏用固定身份（`ScreenConfig.serials`，新屏从 `AppConfig.serialBase` 起），实验屏用 999_000_001 起。colorsyncd 占 CPU 时先数 `/Library/ColorSync/Profiles/Displays/` 下 Snug 的 ICC 有没有变多。删 `.icc` 只给清单和命令，主人自己 sudo

**屏幕与 App 实测**
- 命令行进程读不到它启动后才出现的虚拟屏的模式，每次读都要新起子进程
- 新身份第一次上线是最宽一档，之后按系统记住的那档，所以建屏后要切回目标档
- 原生全屏绕不过最小宽度；辅助功能没有「最小尺寸」属性，只能铺完读回实际大小
- 「打开文件」面板报成标准窗口，按 Cancel 只能用辅助功能；收进菜单栏的 App 不报窗口时唤回不出来；后台启动、没激活过的文本编辑「新建窗口」建出来不显示
- 「新建窗口」菜单名和快捷键照抄在 `NewWindowMenuTests`，别凭 ⌘N 猜

**窗口在 Snug 之外关掉**（#14 仍开着，等报告人验收）：App 关窗当场就存下手机屏上的样子。字号存哪：Ghostty 存窗格、关了就没；终端、iTerm2 跟窗口；VS Code、Cursor 按工作区（尺寸会被重设、缩放还在）；Zed 全 App 共用、只在内存。测 VS Code 用 `code --user-data-dir <短路径>`（socket 路径超 103 字符起不来，用 `$TMPDIR`）；Electron 要先设 `AXManualAccessibility=true`

相关：[[project-product]]、[[project-multi-screen]]
