// 机型库：屏的比例按用户选的型号算（见 ScreenFit），行为按型号的类别标签定（见 ScreenPlan）。
// 机型库 Assets/device-models.json 是唯一的数据源，加机型、改数值都只改它；这里只管解码、校验和查找。
// 文件按类别分三段（手机、平板、电脑），类别写在段上，一条机型不会漏写类别。
// 用户选的那一台连同屏幕数值和类别一起存进配置（DeviceChoice）：启动时按机型名跟机型库对一遍（resolve），数值改过的跟着改；
// 改过名的型号可以用旧名对回，查不到的型号用配置里存下的数值兜底
import Foundation

public struct DeviceCatalog: Equatable, Sendable {
    public struct Brand: Equatable, Sendable, Identifiable {
        public let name: String
        /// 别名：英文名、拼音（「华为」也能用 huawei 搜到）
        public let aliases: [String]
        public let kind: DeviceKind
        /// 按机型库里的顺序（新的在前）
        public let models: [DeviceModel]
        /// 同一个品牌在几个类别里各有一段（Apple 的 iPhone、iPad、Mac）
        public var id: String { "\(kind.rawValue)/\(name)" }
    }

    /// 按文件里的顺序：手机、平板、电脑
    public let brands: [Brand]
    /// 包括配置里可能存着的旧名。2.5 的 iPad 型号是英文，若查不到就会一直按手机扣掉工具栏。
    private let modelsByID: [String: DeviceModel]

    public static let empty = DeviceCatalog()

    private init() {
        brands = []
        modelsByID = [:]
    }

    /// 解码并校验机型库。不合格的条目整份拒收，并写明是哪一条、错在哪：机型库是随 App 发的，错了要在测试里拦下来
    public init(json: Data) throws {
        let file: File
        do {
            file = try JSONDecoder().decode(File.self, from: json)
        } catch {
            throw DeviceCatalogError("解不开：\(error)")
        }
        var seen = Set<String>()
        var modelsByID: [String: DeviceModel] = [:]
        var brands: [Brand] = []
        for kind in DeviceKind.allCases {
            var seenBrands = Set<String>()
            for brand in file[kind] {
                guard !brand.name.isEmpty, !brand.models.isEmpty else { throw DeviceCatalogError("品牌「\(brand.name)」没有名字或没有机型") }
                // 界面按品牌名分节（ForEach 的 id），同一个类别里同一个品牌只能有一段
                guard seenBrands.insert(Self.normalized(brand.name)).inserted else { throw DeviceCatalogError("\(kind.rawValue) 里品牌「\(brand.name)」重复了") }
                let models = try brand.models.map { entry in
                    guard entry.screen.count == 2 else { throw DeviceCatalogError("\(brand.name) \(entry.name)：screen 要写成 [短边, 长边]") }
                    let model = DeviceModel(brand: brand.name, name: entry.name, kind: kind,
                                            screen: DeviceScreen(width: entry.screen[0], height: entry.screen[1], points: entry.points, notch: entry.notch))
                    guard model.screen.isValid else {
                        throw DeviceCatalogError("\(model.id)：分辨率要是正数、短边在前")
                    }
                    for name in [entry.name] + (entry.legacyNames ?? []) {
                        guard !Self.normalized(name).isEmpty else { throw DeviceCatalogError("\(model.id)：型号名不能为空") }
                        let id = "\(brand.name) \(name)"
                        guard seen.insert(Self.normalized(id)).inserted else { throw DeviceCatalogError("\(id)：重复了") }
                        modelsByID[id] = model
                    }
                    return model
                }
                brands.append(Brand(name: brand.name, aliases: brand.aliases ?? [], kind: kind, models: models))
            }
        }
        self.brands = brands
        self.modelsByID = modelsByID
    }

    public init(contentsOf url: URL) throws {
        try self.init(json: try Data(contentsOf: url))
    }

    public var models: [DeviceModel] { brands.flatMap(\.models) }

    /// 这几类的品牌，按机型库里的顺序
    public func brands(in kinds: Set<DeviceKind>) -> [Brand] { brands.filter { kinds.contains($0.kind) } }

    public func model(id: String) -> DeviceModel? {
        modelsByID[id]
    }

    /// 配置里的型号按当前或历史名称对回机型库。自己填的和已找不到的型号沿用原值。
    public func resolve(_ choice: DeviceChoice) -> DeviceChoice {
        guard let id = choice.model, let model = model(id: id) else { return choice }
        return DeviceChoice(model)
    }

    /// 按型号名、品牌名和别名找，不分大小写、不看空格（17promax、mate70、huawei mate 都行）。品牌整个命中就列出全部。
    /// kinds 给了就只在这几类里找
    public func search(_ query: String, in kinds: Set<DeviceKind> = Set(DeviceKind.allCases)) -> [Brand] {
        let q = Self.normalized(query)
        let pool = brands(in: kinds)
        guard !q.isEmpty else { return pool }
        return pool.compactMap { brand in
            let names = ([brand.name] + brand.aliases).map(Self.normalized)
            let models = brand.models.filter { model in
                let name = Self.normalized(model.name)
                return names.contains { ($0 + name).contains(q) }
            }
            return models.isEmpty ? nil : Brand(name: brand.name, aliases: brand.aliases, kind: brand.kind, models: models)
        }
    }

    static func normalized(_ text: String) -> String {
        text.lowercased().filter { !$0.isWhitespace }
    }

    /// 文件的样子：{"phone": [品牌…], "tablet": [品牌…], "computer": [品牌…]}，
    /// 品牌是 {"name", "aliases"?, "models": [{"name", "legacyNames"?, "screen": [短边, 长边], "points"?, "notch"?, "year"}]}。
    /// legacyNames 是旧配置用过的型号名（不带品牌），year 只用于整理时排序
    private struct File: Decodable {
        struct Brand: Decodable {
            let name: String
            let aliases: [String]?
            let models: [Model]
        }

        struct Model: Decodable {
            let name: String
            let legacyNames: [String]?
            let screen: [Int]
            let points: Int?
            let notch: Int?
        }

        let phone: [Brand]
        let tablet: [Brand]?
        let computer: [Brand]?

        subscript(kind: DeviceKind) -> [Brand] {
            switch kind {
            case .phone: phone
            case .tablet: tablet ?? []
            case .computer: computer ?? []
            }
        }
    }
}

public struct DeviceCatalogError: Error, Equatable, CustomStringConvertible {
    public let description: String
    init(_ description: String) { self.description = "机型库：\(description)" }
}
