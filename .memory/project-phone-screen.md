---
name: project-phone-screen
description: 手机屏实现上的实测坑：多数已写进代码注释和 docs/how-it-works.md，这里只留仓库里没有的（UU 事件形态、ColorSync 排障、自测别抢焦点）
metadata:
  node_type: memory
  type: project
  originSessionId: f97709de-705a-489b-bb7a-7353b1fba51c
  modified: 2026-11-13T14:11:51.458Z
---

手机屏的实测结论大多已经写在代码注释和 `docs/how-it-works.md` 里：2 倍门槛（短边 ≥540 点）、按 220ppi 设物理尺寸（460ppi 的新身份永远不上线）、交给帮手进程切模式、屏幕组合一变可能退回 1 倍、加屏前给窗口拍快照、按尺寸 → 位置 → 尺寸的顺序设置并核对、先退出原生全屏、重放事件要打标记、事件监听跑在独立线程。改这些代码前先读注释，别回退。

仓库里没写、但实际踩过的：
- **UU 发来的事件**：点一下是「移动、按下、抬起」；单指滑是「按下、一串左键拖动、抬起」；双指滑是不带相位的像素滚轮；长按是「按下，约 0.7 秒后抬起」。UU 自己没有单指滚动的开关（「平板触控模式」只支持 Windows 被控端）
- **ColorSync 排障**：手机屏只用 3 个固定身份（`PhoneScreenSpec.serials`）。colorsyncd 占 CPU 时，先数 `/Library/ColorSync/Profiles/Displays/` 下的 `Snug 手机屏-*` 有没有变多（变多说明固定身份失效）。删 `.icc` 只给清单和命令，由主人自己 sudo（11-13 已清到只剩真实显示器和当前身份）
- **自测别抢焦点**：放窗口会激活那个 App，自测时别碰主人正在用的窗口
- zsh 里 `log` 是内建命令，查系统日志要写 `/usr/bin/log`

相关：[[project-product]]
