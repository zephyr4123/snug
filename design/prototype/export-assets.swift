// 导出原型用的 SF Symbols 和 App 图标到 design/prototype/assets/（不进 git：苹果的图标不随仓库分发）。
// 用法：swift design/prototype/export-assets.swift
// 符号导出成黑色 PNG，原型里当 CSS mask 用，颜色跟着文字走
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("assets")
let symbolsDir = root.appendingPathComponent("symbols")
let appsDir = root.appendingPathComponent("apps")
try? FileManager.default.createDirectory(at: symbolsDir, withIntermediateDirectories: true)
try? FileManager.default.createDirectory(at: appsDir, withIntermediateDirectories: true)

let symbols = [
    // Mac 端
    "iphone", "ipad.landscape", "ipad", "laptopcomputer", "menubar.rectangle", "hand.tap.fill", "textformat.size",
    "camera.viewfinder", "power", "hand.raised.fill", "record.circle", "arrow.down", "server.rack",
    "iphone.radiowaves.left.and.right", "iphone.slash", "exclamationmark.triangle.fill", "checkmark.circle.fill",
    "rectangle.on.rectangle", "hand.point.up.left", "gearshape", "gearshape.fill", "info.circle", "plus", "minus",
    "chevron.up.chevron.down", "chevron.down", "chevron.right", "square.grid.2x2", "magnifyingglass", "xmark.circle",
    "rectangle.portrait", "rectangle", "display", "checkmark", "info.circle.fill", "rectangle.portrait.rotate", "arrow.left.arrow.right",
    "chevron.compact.right", "chevron.compact.left",
    // Snug 屏上
    "rectangle.portrait.and.arrow.right", "chevron.left", "macwindow.badge.plus", "xmark.square", "xmark.circle.fill",
    "arrow.uturn.backward", "macwindow", "camera", "square.grid.3x3.fill", "list.bullet",
    // 分辨率
    "textformat.size.larger", "textformat.size.smaller",
]

func save(_ image: NSImage, size: NSSize, to url: URL) {
    let scale: CGFloat = 3
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(origin: .zero, size: size))
    NSGraphicsContext.restoreGraphicsState()
    try? rep.representation(using: .png, properties: [:])?.write(to: url)
}

var missing: [String] = []
for name in symbols {
    let config = NSImage.SymbolConfiguration(pointSize: 64, weight: .regular)
    guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config) else {
        missing.append(name)
        continue
    }
    // 画成黑色：原型用透明度当遮罩
    let tinted = NSImage(size: base.size, flipped: false) { rect in
        base.draw(in: rect)
        NSColor.black.set()
        rect.fill(using: .sourceAtop)
        return true
    }
    save(tinted, size: base.size, to: symbolsDir.appendingPathComponent("\(name).png"))
}

let apps: [(String, String)] = [
    ("appstore", "/System/Applications/App Store.app"), ("notes", "/System/Applications/Notes.app"),
    ("maps", "/System/Applications/Maps.app"), ("finder", "/System/Library/CoreServices/Finder.app"),
    ("ghostty", "/Applications/Ghostty.app"), ("calculator", "/System/Applications/Calculator.app"),
    ("calendar", "/System/Applications/Calendar.app"), ("safari", "/Applications/Safari.app"),
    ("reminders", "/System/Applications/Reminders.app"), ("textedit", "/System/Applications/TextEdit.app"),
    ("settings", "/System/Applications/System Settings.app"), ("music", "/System/Applications/Music.app"),
    ("mail", "/System/Applications/Mail.app"), ("preview", "/System/Applications/Preview.app"),
    ("photos", "/System/Applications/Photos.app"), ("terminal", "/System/Applications/Utilities/Terminal.app"),
    ("snug", "/Applications/Snug.app"),
]
for (key, path) in apps {
    guard FileManager.default.fileExists(atPath: path) else { missing.append(path); continue }
    save(NSWorkspace.shared.icon(forFile: path), size: NSSize(width: 128, height: 128), to: appsDir.appendingPathComponent("\(key).png"))
}

// 符号再内嵌成 data URI 写进 symbols.css：Safari 直接打开本地文件时，CSS 遮罩读不了本地图片，内嵌的才显示
var css = "/* 由 export-assets.swift 生成：<i class=\"sym\" data-s=\"符号名\"> */\n"
for name in symbols where !missing.contains(name) {
    guard let data = try? Data(contentsOf: symbolsDir.appendingPathComponent("\(name).png")) else { continue }
    css += ".sym[data-s=\"\(name)\"] { --s: url(\"data:image/png;base64,\(data.base64EncodedString())\"); }\n"
}
try? css.write(to: root.appendingPathComponent("symbols.css"), atomically: true, encoding: .utf8)

print("导出 \(symbols.count - missing.filter { !$0.hasPrefix("/") }.count) 个符号、\(apps.count - missing.filter { $0.hasPrefix("/") }.count) 个 App 图标到 \(root.path)")
if !missing.isEmpty { print("没找到：\(missing.joined(separator: "、"))") }
