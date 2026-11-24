import Foundation
import Testing
@testable import SnugCore

private func app(_ bundle: String, _ name: String) -> AppInfo { AppInfo(bundleID: bundle, name: name, path: "/Applications/\(name).app") }
private func installed(_ bundle: String, _ name: String, english: String? = nil) -> InstalledApp {
    InstalledApp(app(bundle, name), english: english ?? name)
}
private func window(_ pid: Int32, _ id: UInt32, _ title: String = "") -> WindowInfo {
    WindowInfo(key: WindowKey(pid: pid, id: id), app: "App\(pid)", bundleID: "b.\(pid)", title: title)
}
private func running(_ pid: Int32, _ windows: [WindowInfo], bundle: String? = nil) -> RunningApp {
    RunningApp(pid: pid, app: app(bundle ?? "b.\(pid)", "App\(pid)"), windows: windows)
}

private let notesApp = installed("com.apple.Notes", "备忘录", english: "Notes")
private let memos = installed("com.apple.VoiceMemos", "语音备忘录", english: "Voice Memos")
private let ghosttyApp = installed("com.mitchellh.ghostty", "Ghostty")
private let code = installed("com.microsoft.VSCode", "Visual Studio Code", english: "Code")
private let bionic = installed("com.example.bionic", "Bionic")
private let onePassword = installed("com.1password.1password", "1Password")

@Suite("App 资源库 AppList")
struct AppListTests {
    @Test("电脑切换器按窗口位置分组，同一 App 的窗口可在不同组")
    func desktopGroups() {
        let here = window(1, 1, "本屏文档")
        let fullScreen = window(1, 2, "全屏")
        let elsewhere = window(1, 3, "构建日志")
        let unknown = window(4, 4, "位置未知")
        let windowless = running(2, [], bundle: notesApp.id)
        let apps = [running(1, [here, elsewhere, fullScreen]), windowless, running(4, [unknown])]
        let spots: [WindowKey: WindowSpot] = [here.key: .shown(9), fullScreen.key: .fullScreen(9), elsewhere.key: .shown(10)]
        let groups = AppList.desktopGroups(on: 9, query: "", running: apps, installed: [notesApp, code], spots: spots)
        #expect(groups.current == [here, fullScreen])
        #expect(groups.other == [elsewhere, unknown])
        #expect(groups.windowless == [windowless.app])
        #expect(groups.unopened == [code.app])

        let filtered = AppList.desktopGroups(on: 9, query: "构建", running: apps, installed: [notesApp, code], spots: spots)
        #expect(filtered.current.isEmpty && filtered.other == [elsewhere])
        #expect(filtered.windowless.isEmpty && filtered.unopened.isEmpty)
    }

    @Test("拼写：中文转全拼、首字母；英文名就是它自己")
    func keys() {
        #expect(notesApp.keys.sortKey == "bei wang lu")
        #expect(notesApp.keys.initials == "bwl")
        #expect(code.keys.initials == "vsc")
        #expect(installed("com.apple.Pages", "Pages文稿").keys.initials == "pwg")
    }

    @Test("字典序：中文按拼音插在英文中间，数字开头的在最前，同一个 App 装两份只留一份")
    func sorted() {
        let list = AppList.sorted([ghosttyApp, notesApp, bionic, onePassword, code, installed("com.mitchellh.ghostty", "Ghostty 副本")], excluding: [])
        #expect(list.map(\.app.name) == ["1Password", "备忘录", "Bionic", "Ghostty", "Visual Studio Code"])
    }

    @Test("远控自己的 App 不出现在全部 App 和在跑的 App 里（不管是不是第一次刷新）；名单外的照常")
    func excludesRemotes() {
        let hidden: Set<String> = ["com.example.jia", "com.example.yi"]
        #expect(AppList.sorted([installed("com.example.jia", "甲远程"), ghosttyApp], excluding: hidden).map(\.app.name) == ["Ghostty"])
        let fresh = [running(1, [], bundle: "com.example.yi"), running(2, [])]
        #expect(AppList.refreshed(fresh, shown: [], reorder: true, excluding: hidden).map(\.pid) == [2])
        #expect(AppList.refreshed(fresh, shown: [running(2, [])], reorder: false, excluding: hidden).map(\.pid) == [2])
        #expect(AppList.refreshed(fresh, shown: [], reorder: true, excluding: []).map(\.pid) == [1, 2])
    }

    @Test("刷新：第一次用新读到的顺序；之后保持露着时的顺序，新出现的接在后面")
    func refreshedKeepsOrder() {
        let shown = [running(2, []), running(1, [])]
        let fresh = [running(1, []), running(3, []), running(2, [])]
        #expect(AppList.refreshed(fresh, shown: shown, reorder: true, excluding: []).map(\.pid) == [1, 3, 2])
        #expect(AppList.refreshed(fresh, shown: shown, reorder: false, excluding: []).map(\.pid) == [2, 1, 3])
    }

    @Test("搜索：中文名、英文名、全拼、首字母都能搜到；开头就对上的排前面，只是包含的排后面")
    func searchApps() {
        let all = AppList.sorted([notesApp, memos, ghosttyApp, code], excluding: [])
        #expect(AppList.search("bei", installed: all, running: []).apps.map(\.name) == ["备忘录", "语音备忘录"])
        #expect(AppList.search("bwl", installed: all, running: []).apps.map(\.name) == ["备忘录"])
        #expect(AppList.search("备忘", installed: all, running: []).apps.map(\.name) == ["备忘录", "语音备忘录"])
        #expect(AppList.search("notes", installed: all, running: []).apps.map(\.name) == ["备忘录"])
        #expect(AppList.search("VSC", installed: all, running: []).apps.map(\.name) == ["Visual Studio Code"])
        #expect(AppList.search("studio code", installed: all, running: []).apps.map(\.name) == ["Visual Studio Code"])
    }

    @Test("搜索：窗口标题也搜；空白的查询什么都不出；对不上就是空的")
    func searchWindows() {
        let apps = [running(1, [window(1, 10, "~/projects/snug — zsh")]), running(2, [window(2, 20, "Issues · snug")])]
        let result = AppList.search("snug", installed: [], running: apps)
        #expect(result.windows.map(\.key.id) == [10, 20])
        #expect(AppList.search("  ", installed: [ghosttyApp], running: apps).isEmpty)
        #expect(AppList.search("xyz", installed: [ghosttyApp], running: apps).isEmpty)
    }

    @Test("搜索：在跑却不在常规目录里的 App 也搜得到，装着的不重复")
    func searchRunningOnly() {
        let dev = RunningApp(pid: 5, app: app("com.example.dev", "开发版"), windows: [])
        let ghosttyRunning = RunningApp(pid: 6, app: ghosttyApp.app, windows: [])
        let result = AppList.search("kai", installed: [ghosttyApp], running: [dev, ghosttyRunning])
        #expect(result.apps.map(\.name) == ["开发版"])
        #expect(AppList.search("gh", installed: [ghosttyApp], running: [ghosttyRunning]).apps.count == 1)
    }

    @Test("在跑的 App 按最近用过排：App 按最前的窗口，App 里的窗口按前后层次；没窗口的和别的桌面上的排后面、保持原顺序")
    func ordered() {
        let apps = [running(1, [window(1, 11), window(1, 12)]), running(2, []), running(3, [window(3, 31)]), running(4, [window(4, 41)])]
        let list = AppList.ordered(apps, frontToBack: [31, 12, 11])
        #expect(list.map(\.pid) == [3, 1, 2, 4])
        #expect(list[1].windows.map(\.key.id) == [12, 11])
    }

    @Test("列表露着时不换位置：还在的按原顺序（内容用新的），新的接在后面，没了的去掉；App 里的窗口也一样")
    func keepingOrder() {
        let shown = [running(1, [window(1, 11), window(1, 12)]), running(2, []), running(3, [window(3, 31)])]
        // 刷新回来：App 3 跑到最前，App 2 退了，App 4 新开；App 1 的窗口 11 关了、新开了 13，12 换了标题
        let fresh = [running(3, [window(3, 31)]), running(4, []), running(1, [window(1, 13), window(1, 12, "新标题")])]
        let kept = AppList.keepingOrder(of: shown, updatedWith: fresh)
        #expect(kept.map(\.pid) == [1, 3, 4])
        #expect(kept[0].windows.map(\.key.id) == [12, 13])
        #expect(kept[0].windows.first?.title == "新标题")
    }

    @Test("点一个 App：在跑且有窗口就放最近用过的那个；在跑没窗口、没在跑就打开它")
    func action() {
        let ghosttyRunning = RunningApp(pid: 6, app: ghosttyApp.app, windows: [window(6, 61), window(6, 62)])
        let notesRunning = RunningApp(pid: 7, app: notesApp.app, windows: [])
        let apps = [ghosttyRunning, notesRunning]
        #expect(AppList.action(for: ghosttyApp.app, running: apps) == .pull(window(6, 61)))
        #expect(AppList.action(for: notesApp.app, running: apps) == .open(notesApp.app))
        #expect(AppList.action(for: code.app, running: apps) == .open(code.app))
    }

    @Test("按首字母分组：中文按拼音首字母，数字、符号、表情开头的归到最后的 #，组内保持原顺序")
    func grouped() {
        let list = AppList.sorted([ghosttyApp, notesApp, bionic, onePassword, code, memos, installed("x.emoji", "🎵 音乐")], excluding: [])
        let groups = AppList.grouped(list)
        #expect(groups.map(\.letter) == ["B", "G", "V", "Y", "#"])
        #expect(groups.map { $0.apps.map(\.app.name) } == [["备忘录", "Bionic"], ["Ghostty"], ["Visual Studio Code"], ["语音备忘录"],
                                                          ["🎵 音乐", "1Password"]])
        #expect(AppList.grouped([]).isEmpty)
    }

    @Test("访达不给退出：Mac 上它的菜单、程序坞里都没有「退出」")
    func canQuit() {
        #expect(!AppList.canQuit(app("com.apple.finder", "访达")))
        #expect(AppList.canQuit(ghosttyApp.app))
    }
}
