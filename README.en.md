<div align="center">

[简体中文](README.md) · **English**

<img src="Assets/AppIcon/AppIcon-1024.png" width="128" alt="Snug icon">

# Snug

**A native-grade Mac experience, right on your phone**

A mobile workspace built for UU Remote<br>Dedicated portrait screen · Full-screen windows · Larger text · iOS-style gestures

[![Latest release](https://img.shields.io/github/v/release/zephyr4123/snug?label=release&color=blue)](https://github.com/zephyr4123/snug/releases/latest) ![Apple Silicon · Intel](https://img.shields.io/badge/Apple%20Silicon%20%C2%B7%20Intel-Universal-success) ![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue) ![Notarized](https://img.shields.io/badge/Apple-Notarized-black?logo=apple) [![License MIT](https://img.shields.io/badge/License-MIT-green)](LICENSE)

[Download](#-download) · [Highlights](#-highlights) · [Interactions](#-iphone-native-interactions) · [Comparison](#-compared-with-alternatives) · [Installation](#-installation) · [Usage](#-usage) · [Limitations](#-known-limitations) · [Development](#-development)

<br>

<img src="https://dl.zephyrxiang.com/snug/media/phone-window-list.7edc548b.png" width="30%" alt="Window list"> <img src="https://dl.zephyrxiang.com/snug/media/phone-demo.2cee4e81.webp" width="30%" alt="Live demo: opening a window, typing commands on the pop-up keyboard, resuming a session, one-finger scrolling, returning to the list"> <img src="https://dl.zephyrxiang.com/snug/media/phone-context-menu.997dd70f.png" width="30%" alt="Long-press context menu">
<p><sub>Window list · Live demo · Long-press context menu</sub><br><sub>▶ <a href="https://dl.zephyrxiang.com/snug/media/phone-demo.a97e46d1.mp4">Watch the HD demo video</a></sub></p>

</div>

> Snug continues [aoyamashou/UUyc-companion](https://github.com/aoyamashou/UUyc-companion) (UU Remote Companion by AoyamaShou, MIT License), with the original author's copyright notices and commit history fully preserved. Since version 2.0, it has been redesigned around the phone screen.

## 📥 Download

<img src="Assets/AppIcon/AppIcon-1024.png" width="88" align="left" alt="Snug icon">

**Snug for macOS** [![Latest release](https://img.shields.io/github/v/release/zephyr4123/snug?label=release&color=blue)](https://github.com/zephyr4123/snug/releases/latest)<br>A single universal package for Apple silicon and Intel, running on macOS 14 or later<br>Signed and notarized by Apple; simply drag it into Applications

<br clear="left">

| Source | Notes | Download |
| :--- | :--- | :--- |
| **China mirror** | Served via Tencent Cloud CDN; recommended in mainland China | [Snug.dmg](https://dl.zephyrxiang.com/snug/latest/Snug.dmg) |
| **GitHub Releases** | Release notes, checksums, and previous versions | [Go to Releases](https://github.com/zephyr4123/snug/releases/latest) |

Both sources provide the identical package.

## ✨ Highlights

UU Remote scales your entire desktop down to fit the phone. Snug adds a dedicated portrait display for the phone, presenting your Mac's windows at a phone-native scale.

<p align="center"><img src="https://dl.zephyrxiang.com/snug/media/compare-uu-original.cf4158d1.png" width="36%" alt="UU Remote alone: the whole desktop squeezed onto the phone"> <img src="https://dl.zephyrxiang.com/snug/media/phone-claude-code.93e21d9d.png" width="36%" alt="With Snug: the window fills the screen with larger text"><br><sub>Same content · Left: UU Remote alone · Right: with Snug</sub></p>

| | UU Remote alone | With Snug |
| :--- | :--- | :--- |
| **Display** | The whole desktop is scaled down; text and controls shrink several times over | A dedicated portrait screen that each window fills completely |
| **Text size** | Shrinks along with the desktop | Enlarged automatically in terminals and editors |
| **One-finger swipe** | Interpreted as a mouse drag | Scrolls the page, with momentum |
| **Switching windows** | Hunt for them on a shrunken desktop | Pick from a window list with a single tap |

- When the session ends, windows return to their original positions and text sizes are restored
- When you are not on the phone screen, UU Remote behaves exactly as it always has

## 📱 iPhone-Native Interactions

| iPhone | Snug phone screen |
| :--- | :--- |
| App Switcher | Window list, gathering every window on your Mac |
| Opening an app | Selecting a window gives it the entire screen |
| Home indicator | Bottom indicator bar, returning to the window list |
| "‹ Back" in the top-left corner | "‹ App name" in the top-left corner, returning to the current window |
| Dynamic Type | Text scales up for the screen, remembered per app |

### Gestures, Redesigned for Touch

UU Remote's mobile client carries over trackpad gesture conventions. On the phone screen, Snug reinterprets them the way phones are meant to be used.

| On the phone | UU Remote alone | Snug phone screen |
| :--- | :--- | :--- |
| One-finger swipe | Mouse drag, often selecting text by accident | Scrolls, with momentum after release |
| Long-press, then drag | Mouse drag | Selects text |
| Long-press, then release | Regular click | Opens the context menu |

- Applies only within the phone screen; other displays and the Mac's own trackpad and mouse are unaffected

## 🆚 Compared with Alternatives

| Approach | Limitation | Snug |
| :--- | :--- | :--- |
| **Remote control in AI assistants** | Limited to that vendor's own AI sessions | Works with any terminal or app |
| **UU Remote's built-in terminal** | Separate from local terminals; processes linger after disconnecting | Uses the terminal windows already open on your Mac |
| **UU Remote's default gestures** | Trackpad conventions | Redesigned for touch; see [Gestures](#gestures-redesigned-for-touch) |

- **Remote control in AI assistants**: for example, Claude Remote Control and Codex in ChatGPT, each tied to a single product
- **UU Remote's built-in terminal**: runs in UU Remote's own tmux, isolated from the terminals already open on your Mac, so work in progress (such as Claude Code running in your terminal) cannot be picked up there; after disconnecting, the session and its processes keep running in the background

**Not tied to any AI vendor**: Snug brings the Mac's windows themselves to the phone screen, so Claude Code in a terminal and Codex in a desktop app both work as they are.

<p align="center"><img src="https://dl.zephyrxiang.com/snug/media/phone-claude-code.93e21d9d.png" width="36%" alt="Claude Code in a terminal, filling the Snug phone screen"> <img src="https://dl.zephyrxiang.com/snug/media/phone-chatgpt.a28ef053.png" width="36%" alt="Codex in the ChatGPT desktop app, filling the Snug phone screen"><br><sub>Left: Claude Code in a terminal · Right: Codex in the ChatGPT desktop app (file links redacted)</sub></p>

## 📦 Installation

> **Requirements**: macOS 14 or later, with [UU Remote](https://uuyc.163.com/) installed on the Mac being controlled. On the phone, only UU Remote is needed.

**Download and install (recommended)**

1. Get the installer from the [Download](#-download) section (the China mirror is recommended in mainland China)
2. Drag Snug into Applications and open it
3. Grant the Accessibility permission when the welcome window prompts you (the setting was renamed in macOS 27)

Snug then stays in the menu bar; no further setup is needed. Open Snug again at any time to bring up Settings.

**Updates**: Snug checks for a new version each time it starts. When one is available, it lists what changed in every newer version and installs with one click, downloading only the parts that changed and keeping your settings and permissions. You can also check manually in About Snug (「关于 Snug」), or switch the update source between Tencent Cloud (「腾讯云」) and GitHub. In-app updates are available from 2.1.0; replace earlier versions manually.

<div align="center">
<img src="https://dl.zephyrxiang.com/snug/media/welcome.57ad51da.png" width="45%" alt="Welcome window"> <img src="https://dl.zephyrxiang.com/snug/media/settings-ready.482119c9.png" width="45%" alt="Settings">
<p><sub>Welcome window · Settings</sub></p>
</div>

**Build from source** (requires Xcode and Swift 6)

```bash
git clone https://github.com/zephyr4123/snug.git
cd snug && scripts/snug install
```

<details>
<summary>Migrating from UU Remote Companion</summary>

Running both at the same time causes conflicts, so Snug prompts you to quit the old app at launch. If you enabled its watchdog helper, also run:

```bash
launchctl bootout gui/$(id -u)/com.corndog.uudisplay.watchdog-agent
rm ~/Library/LaunchAgents/com.corndog.uudisplay.watchdog-agent.plist
```

</details>

## 🧭 Usage

1. **Switch screens**: once a phone or tablet connects, choose "Snug 手机屏" (Snug Phone Screen) in UU Remote's screen list

   <img src="https://dl.zephyrxiang.com/snug/media/uu-screen-picker.212fdbe9.png" width="50%" alt="UU Remote's screen list, showing display 3: Snug Phone Screen">

2. **Pick a window**: tap any window in the list and it fills the screen
3. **Switch windows**: tap the bottom indicator bar to return to the list; choosing another window returns the previous one to its place
4. **End the session**: windows return to their original positions, text sizes are restored, and the phone screen is removed

## 🔒 Isolation and Restoration

- **Only the phone screen is touched**: the main display, other screens, and other windows are left alone
- **Record first, then change**: each window's original position and text size are recorded in advance, so they can be restored even if Snug quits unexpectedly
- **Unresponsive apps are left as they are**: if an app stops responding, Snug does not force its window to move and explains why on screen
- **No network access**: Snug connects to no servers and collects no data

## 🚧 Known Limitations

| Limitation | Details |
| :--- | :--- |
| Relies on undocumented macOS APIs | May break after a major macOS update |
| Screen proportions match the iPhone 17 Pro Max | Other models may show slight letterboxing; portrait only |
| Some windows cannot fill the screen | Apps such as System Settings and Safari enforce a minimum width; their windows are left-aligned |
| Text enlargement covers terminals and editors only | Ghostty, Terminal, iTerm2, VS Code, Cursor, and Zed; browsers are not adjusted |
| Not an official NetEase product | Unaffiliated with UU Remote or its developer; UU Remote updates may affect some features |
| The phone screen may occasionally remain after a session ends | Occurs when the system log misses the end of the stream; the menu bar still shows the session as active (「远程中」). Turn off the phone screen in Settings to restore |

The technical reasons behind each limitation are explained in [How It Works](docs/how-it-works.md#已知限制的技术原因) (in Chinese).

## 🔧 Development

```bash
scripts/snug check     # build and run all tests
scripts/snug install   # build, install, and launch
```

- The code is organized in three layers: `SnugCore` (pure logic) → `SnugSystem` (system interfaces) → `Snug` (UI)
- Packaging, releases, launch arguments, and data locations: [Development guide](docs/development.md) (in Chinese)
- Connection detection, window placement, and gesture translation: [How It Works](docs/how-it-works.md) (in Chinese)

## 🧹 Uninstall

1. Quit Snug from the menu bar (windows are restored first)
2. Move Snug from Applications to the Trash
3. Optional: remove its settings and logs with `rm -rf ~/Library/Application\ Support/Snug ~/Library/Logs/Snug.log*`
4. Optional: remove Snug from Accessibility in System Settings

## 🙏 Acknowledgments

First and foremost, we extend our sincere respect to **[UU Remote](https://uuyc.163.com/)**.

- **Exceptional quality**: stable connections, responsive control, and freely adjustable image quality and frame rate. Remote control spans encoding, transport, and connectivity across networks, among many other engineering challenges; reaching a standard that everyday work can depend on is a formidable technical achievement in its own right.
- **Entirely free**: a product with so high a technical barrier remains free for everyone. That goes well beyond generosity; it is a genuine gift to the entire remote-access ecosystem. This openness is what allows the community to keep building on it, from companion apps and one-finger scrolling to virtual displays, and Snug grew from it as well.

With heartfelt thanks.

We are equally grateful to the following projects and contributors:

- [UUyc-companion](https://github.com/aoyamashou/UUyc-companion) (MIT): by AoyamaShou, Snug's predecessor
- [Better Remote](https://github.com/pincc-debug/better-remote) (MIT): by pincc-debug, the approach to one-finger scrolling in UU Remote
- [PermissionFlow](https://github.com/jaywcjlove/PermissionFlow) (MIT): by jaywcjlove (小弟调调), the permission onboarding and drag-to-authorize panel
- [FreeDisplay](https://github.com/huberdf/FreeDisplay) (MIT): by huberdf, the `CGVirtualDisplay` interface declarations
- Community PR authors: bubble, gencheng liu, and Rongzheng Liu (#10, reading UU Remote windows in full-screen Spaces)
- The virtual display implementation draws on [DeskPad](https://github.com/Stengo/DeskPad), [Side Screen](https://github.com/tranvuongquocdat/SideScreen), and Chromium

## 📄 License

[MIT](LICENSE) © 2026 AoyamaShou, © 2026 zephyr4123
