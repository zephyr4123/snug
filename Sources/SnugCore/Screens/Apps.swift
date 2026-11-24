// App 资源库的数据：App 的身份、本机装着的 App、在跑的 App 和它的窗口，以及排序、搜索、点一下做什么。
// 全是纯逻辑：系统怎么读出这些归 SnugSystem（AppService、WindowService），界面只读 Snug 里的 AppCatalog
import Foundation

/// 一个 App 的身份。按 bundle ID 认：装着的、在跑的是同一个 App
public struct AppInfo: Hashable, Sendable, Identifiable {
    public let bundleID: String
    /// 显示名：按 Snug 的界面语言（简体中文）取，系统 App 是「备忘录」「终端」，系统语言是英文也一样
    public let name: String
    /// .app 的路径：启动、取图标用。在跑的 App 偶尔读不到
    public let path: String?

    public init(bundleID: String, name: String, path: String?) {
        self.bundleID = bundleID
        self.name = name
        self.path = path
    }

    public var id: String { bundleID }
}

/// 本机装着的一个 App，带搜索用的拼写
public struct InstalledApp: Equatable, Sendable, Identifiable {
    public let app: AppInfo
    public let keys: SearchKeys

    /// english：Info.plist 里的名字（系统 App 的英文名，如 Notes）
    public init(_ app: AppInfo, english: String) {
        self.app = app
        keys = SearchKeys(name: app.name, english: english)
    }

    public var id: String { app.bundleID }
}

/// 在跑的一个 App 和它此刻的窗口（没有窗口的也算：点了红色关闭按钮的 App 往往还在跑）
public struct RunningApp: Equatable, Sendable, Identifiable {
    public let pid: Int32
    public let app: AppInfo
    public var windows: [WindowInfo]

    public init(pid: Int32, app: AppInfo, windows: [WindowInfo]) {
        self.pid = pid
        self.app = app
        self.windows = windows
    }

    public var id: Int32 { pid }
}

/// 搜索、排序用的拼写：显示名、英文名、全拼、首字母（备忘录 → bei wang lu → bwl）。
/// 拼音由 Foundation 的 mandarinToLatin 转出、去掉声调；本来就是英文的名字拼音就是它自己
public struct SearchKeys: Equatable, Sendable {
    /// 比对用：去掉空白、转小写
    let words: [String]
    let initials: String
    /// 字典序：中文按拼音插在英文中间（备忘录排在 B）
    public let sortKey: String

    public init(name: String, english: String) {
        let latin = (name.applyingTransform(.mandarinToLatin, reverse: false) ?? name)
            .applyingTransform(.stripDiacritics, reverse: false) ?? name
        let pinyin = latin.lowercased()
        words = [name, english, pinyin].map(Self.normalized)
        initials = pinyin.split(whereSeparator: \.isWhitespace).compactMap(\.first).map(String.init).joined()
        sortKey = pinyin
    }

    /// 对得上的程度：开头就对上（含首字母开头）2，包含 1，不沾边 0
    func score(_ query: String) -> Int {
        let q = Self.normalized(query)
        guard !q.isEmpty else { return 0 }
        if words.contains(where: { $0.hasPrefix(q) }) || initials.hasPrefix(q) { return 2 }
        return words.contains { $0.contains(q) } ? 1 : 0
    }

    static func normalized(_ text: String) -> String {
        text.lowercased().filter { !$0.isWhitespace }
    }
}

public enum AppList {
    /// 不给退出的 App：访达。同 Mac，它的菜单、程序坞里都没有「退出」（实测 11-14 terminate 能退掉，桌面图标跟着没了）
    private static let unquittableBundles: Set<String> = ["com.apple.finder"]

    public static func canQuit(_ app: AppInfo) -> Bool { !unquittableBundles.contains(app.bundleID) }

    /// 在跑的 App 按最近用过排，和 iPhone 的多任务界面一样：App 按它最前面那个窗口排，App 里的窗口也按前后层次排。
    /// frontToBack 是屏上窗口从前到后的编号；不在里面的窗口（别的桌面上的）、没有窗口的 App 排后面，彼此保持原顺序
    public static func ordered(_ apps: [RunningApp], frontToBack: [UInt32]) -> [RunningApp] {
        let rank = Dictionary(frontToBack.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        func position(_ window: WindowInfo) -> Int { rank[window.key.id] ?? Int.max }
        return stableSorted(apps.map { app in
            var app = app
            app.windows = stableSorted(app.windows, by: position)
            return app
        }) { $0.windows.first.map(position) ?? Int.max }
    }

    /// 列表露着时不换位置：手指正要点，卡片挪了位置就会点到别的上（放上来的窗口拿到焦点，下次刷新就会排到最前）。
    /// 还在的 App 和窗口按原来的顺序、用新的内容；新出现的接在后面；没了的去掉。下次露出列表时才按最近用过重排
    public static func keepingOrder(of shown: [RunningApp], updatedWith fresh: [RunningApp]) -> [RunningApp] {
        let latest = Dictionary(fresh.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        let known = Set(shown.map(\.pid))
        let kept = shown.compactMap { old -> RunningApp? in
            guard var app = latest[old.pid] else { return nil }
            app.windows = keepingOrder(of: old.windows, updatedWith: app.windows)
            return app
        }
        return kept + fresh.filter { !known.contains($0.pid) }
    }

    static func keepingOrder(of shown: [WindowInfo], updatedWith fresh: [WindowInfo]) -> [WindowInfo] {
        let latest = Dictionary(fresh.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        let known = Set(shown.map(\.key))
        return shown.compactMap { latest[$0.key] } + fresh.filter { !known.contains($0.key) }
    }

    /// 刷新后列表里的在跑 App：去掉 excluded 里的（见 sorted）；reorder 时用新读到的顺序（已按最近用过排），
    /// 否则保持列表露着时的顺序（见 keepingOrder）
    public static func refreshed(_ fresh: [RunningApp], shown: [RunningApp], reorder: Bool, excluding excluded: Set<String>) -> [RunningApp] {
        let listed = fresh.filter { !excluded.contains($0.app.bundleID) }
        return reorder ? listed : keepingOrder(of: shown, updatedWith: listed)
    }

    /// 全部 App 按字典序，同一个 App 装了两份（比如「应用程序」和用户目录各一份）只留第一份。
    /// excluded 不出现在资源库里：各家远控自己的 App（RemoteIdentity.bundleIDs，按登记的远控给），
    /// 把遥控器放到 Snug 的屏上没有意义，退了它远程就断了
    public static func sorted(_ apps: [InstalledApp], excluding excluded: Set<String>) -> [InstalledApp] {
        var seen = Set<String>()
        return apps
            .filter { !excluded.contains($0.app.bundleID) && seen.insert($0.app.bundleID).inserted }
            .sorted { $0.keys.sortKey.localizedStandardCompare($1.keys.sortKey) == .orderedAscending }
    }

    /// 首字母相同的一组 App
    public struct LetterGroup: Equatable, Sendable, Identifiable {
        public let letter: String
        public let apps: [InstalledApp]
        public var id: String { letter }
    }

    /// 按首字母分组（搜索页空着时，同 iOS 的 App 资源库）：中文按拼音首字母，数字、符号、表情开头的归到最后的 #。
    /// 组按字母排，组内保持传进来的顺序（传 sorted 的结果就是字典序）
    public static func grouped(_ apps: [InstalledApp]) -> [LetterGroup] {
        let groups = Dictionary(grouping: apps) { app -> String in
            guard let first = app.keys.sortKey.first, first.isASCII, first.isLetter else { return "#" }
            return first.uppercased()
        }
        return groups
            .sorted { ($0.key == "#" ? 1 : 0, $0.key) < ($1.key == "#" ? 1 : 0, $1.key) }
            .map { LetterGroup(letter: $0.key, apps: $0.value) }
    }

    public struct SearchResult: Equatable, Sendable {
        public var apps: [AppInfo]
        public var windows: [WindowInfo]
        public var isEmpty: Bool { apps.isEmpty && windows.isEmpty }
    }

    /// 搜 App 名（中文、英文、全拼、首字母）和窗口标题。开头就对上的排前面，同分按字典序（installed 已排好）。
    /// 在跑却不在常规目录里的 App（开发中的、从下载目录直接打开的）也搜得到
    public static func search(_ query: String, installed: [InstalledApp], running: [RunningApp]) -> SearchResult {
        let installedIDs = Set(installed.map(\.app.bundleID))
        let candidates = installed + running.filter { !installedIDs.contains($0.app.bundleID) }
            .map { InstalledApp($0.app, english: $0.app.name) }
        let apps = stableSorted(candidates.map { ($0, $0.keys.score(query)) }.filter { $0.1 > 0 }) { -$0.1 }.map(\.0.app)
        let q = SearchKeys.normalized(query)
        let windows = q.isEmpty ? [] : running.flatMap(\.windows).filter { SearchKeys.normalized($0.title).contains(q) }
        return SearchResult(apps: apps, windows: windows)
    }

    public struct DesktopGroups {
        public var current: [WindowInfo] = []
        public var other: [WindowInfo] = []
        public var windowless: [AppInfo] = []
        public var unopened: [AppInfo] = []
    }

    public static func desktopGroups(on display: DisplayID, query: String, running: [RunningApp],
                                     installed: [InstalledApp], spots: [WindowKey: WindowSpot]) -> DesktopGroups {
        var groups = DesktopGroups()
        let matches = query.isEmpty ? nil : search(query, installed: installed, running: running)
        let appIDs = matches.map { Set($0.apps.map(\.bundleID)) }
        let windowKeys = Set(matches?.windows.map(\.key) ?? [])
        let runningIDs = Set(running.map { $0.app.bundleID })

        for entry in running {
            let appMatches = appIDs?.contains(entry.app.bundleID) ?? true
            if entry.windows.isEmpty, appMatches { groups.windowless.append(entry.app) }
            for window in entry.windows where appMatches || windowKeys.contains(window.key) {
                let spot = spots[window.key]
                if spot == .shown(display) || spot == .fullScreen(display) {
                    groups.current.append(window)
                } else {
                    groups.other.append(window)
                }
            }
        }
        groups.unopened = installed.map(\.app).filter {
            !runningIDs.contains($0.bundleID) && (appIDs?.contains($0.bundleID) ?? true)
        }
        return groups
    }

    /// 点一个 App（App 行、全部页里的图标、搜索结果）做什么：同点 Dock 图标，但窗口落在这块屏上。
    /// 在跑且有窗口 → 放最近用过的那个；在跑但没窗口、没在跑 → 打开它，等新窗口出来再放
    public enum Action: Equatable, Sendable {
        case pull(WindowInfo)
        case open(AppInfo)
    }

    public static func action(for app: AppInfo, running: [RunningApp]) -> Action {
        if let window = running.first(where: { $0.app.bundleID == app.bundleID })?.windows.first { return .pull(window) }
        return .open(app)
    }

    /// 按 key 排序，key 相同的保持原顺序
    private static func stableSorted<T>(_ items: [T], by key: (T) -> Int) -> [T] {
        items.enumerated().sorted { (key($0.element), $0.offset) < (key($1.element), $1.offset) }.map(\.element)
    }
}
