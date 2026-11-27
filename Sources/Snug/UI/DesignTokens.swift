// 生成的，不要手改：改 design/design-tokens.json，再运行 SNUG_WRITE_TOKENS=1 swift test --filter DesignTokensTests。
// 带 system 的颜色用系统语义色；只有 light / dark 的按外观取（iOS 的分组背景色 macOS 上没有）
import AppKit
import SwiftUI

enum MacTokens {
    enum Color {
        static let accent = SwiftUI.Color(nsColor: .controlAccentColor)
        static let accentFill = SwiftUI.Color(nsColor: .dynamic(light: .controlAccentColor.withAlphaComponent(0.14), dark: .controlAccentColor.withAlphaComponent(0.22)))
        static let controlBackground = SwiftUI.Color(nsColor: .controlColor)
        static let controlBorder = SwiftUI.Color(nsColor: .dynamic(light: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.12), dark: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.1)))
        static let danger = SwiftUI.Color(nsColor: .systemRed)
        static let fill = SwiftUI.Color(nsColor: .dynamic(light: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.05), dark: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.07)))
        static let groupBackground = SwiftUI.Color(nsColor: .dynamic(light: NSColor(srgbRed: 0.961, green: 0.961, blue: 0.961, alpha: 1), dark: NSColor(srgbRed: 0.224, green: 0.224, blue: 0.224, alpha: 1)))
        static let groupBorder = SwiftUI.Color(nsColor: .dynamic(light: NSColor(srgbRed: 0.898, green: 0.898, blue: 0.898, alpha: 1), dark: NSColor(srgbRed: 0.282, green: 0.282, blue: 0.282, alpha: 1)))
        static let label = SwiftUI.Color(nsColor: .labelColor)
        static let menuBackground = SwiftUI.Color(nsColor: .dynamic(light: NSColor(srgbRed: 0.965, green: 0.965, blue: 0.965, alpha: 0.92), dark: NSColor(srgbRed: 0.157, green: 0.157, blue: 0.157, alpha: 0.92)))
        static let menuHighlight = SwiftUI.Color(nsColor: .selectedContentBackgroundColor)
        static let positive = SwiftUI.Color(nsColor: .systemGreen)
        static let previewBezel = SwiftUI.Color(nsColor: .dynamic(light: NSColor(srgbRed: 0.11, green: 0.11, blue: 0.118, alpha: 1), dark: NSColor(srgbRed: 0.11, green: 0.11, blue: 0.118, alpha: 1)))
        static let previewMenuBar = SwiftUI.Color(nsColor: .dynamic(light: NSColor(srgbRed: 0.294, green: 0.376, blue: 0.51, alpha: 1), dark: NSColor(srgbRed: 0.294, green: 0.376, blue: 0.51, alpha: 1)))
        static let previewScreen = SwiftUI.Color(nsColor: .dynamic(light: NSColor(srgbRed: 0.118, green: 0.118, blue: 0.118, alpha: 1), dark: NSColor(srgbRed: 0.118, green: 0.118, blue: 0.118, alpha: 1)))
        static let previewText = SwiftUI.Color(nsColor: .dynamic(light: NSColor(srgbRed: 0.839, green: 0.839, blue: 0.839, alpha: 1), dark: NSColor(srgbRed: 0.839, green: 0.839, blue: 0.839, alpha: 1)))
        static let previewTitle = SwiftUI.Color(nsColor: .dynamic(light: NSColor(srgbRed: 0.659, green: 0.659, blue: 0.678, alpha: 1), dark: NSColor(srgbRed: 0.659, green: 0.659, blue: 0.678, alpha: 1)))
        static let previewTitleBar = SwiftUI.Color(nsColor: .dynamic(light: NSColor(srgbRed: 0.165, green: 0.165, blue: 0.176, alpha: 1), dark: NSColor(srgbRed: 0.165, green: 0.165, blue: 0.176, alpha: 1)))
        static let secondaryLabel = SwiftUI.Color(nsColor: .secondaryLabelColor)
        static let separator = SwiftUI.Color(nsColor: .separatorColor)
        static let tertiaryLabel = SwiftUI.Color(nsColor: .tertiaryLabelColor)
        static let warning = SwiftUI.Color(nsColor: .systemOrange)
        static let windowBackground = SwiftUI.Color(nsColor: .windowBackgroundColor)
    }
    enum Font {
        static let body = FontToken(size: 13, weight: .regular, lineHeight: 16)
        static let callout = FontToken(size: 12, weight: .regular, lineHeight: 15)
        static let code = FontToken(size: 12, weight: .regular, lineHeight: 16)
        static let footnote = FontToken(size: 10, weight: .regular, lineHeight: 13)
        static let headline = FontToken(size: 13, weight: .semibold, lineHeight: 16)
        static let largeTitle = FontToken(size: 26, weight: .regular, lineHeight: 32)
        static let title1 = FontToken(size: 22, weight: .regular, lineHeight: 26)
        static let title2 = FontToken(size: 17, weight: .regular, lineHeight: 22)
        static let title3 = FontToken(size: 15, weight: .regular, lineHeight: 20)
    }
    enum IconTile {
        static let accessibility = TileToken(color: SwiftUI.Color(nsColor: .systemIndigo), symbol: "hand.raised.fill")
        static let gestures = TileToken(color: SwiftUI.Color(nsColor: .systemOrange), symbol: "hand.tap.fill")
        static let launchAtLogin = TileToken(color: SwiftUI.Color(nsColor: .systemGray), symbol: "power")
        static let mainScreen = TileToken(color: SwiftUI.Color(nsColor: .systemIndigo), symbol: "menubar.rectangle")
        static func screen(symbol: String) -> TileToken { TileToken(color: SwiftUI.Color(nsColor: .systemBlue), symbol: symbol) }
        static let screenRecording = TileToken(color: SwiftUI.Color(nsColor: .systemRed), symbol: "record.circle")
        static let screenshot = TileToken(color: SwiftUI.Color(nsColor: .systemPink), symbol: "camera.viewfinder")
        static let update = TileToken(color: SwiftUI.Color(nsColor: .systemBlue), symbol: "arrow.down")
        static let updateSource = TileToken(color: SwiftUI.Color(nsColor: .systemGray), symbol: "server.rack")
        static let zoom = TileToken(color: SwiftUI.Color(nsColor: .systemGreen), symbol: "textformat.size")
    }
    enum Radius {
        static let control: CGFloat = 6
        static let group: CGFloat = 10
        static let iconTile: CGFloat = 6
        static let libraryTab: CGFloat = 10
        static let menu: CGFloat = 10
        static let sheet: CGFloat = 12
        static let statusTile: CGFloat = 10
        static let window: CGFloat = 16
    }
    enum Size {
        static let aboutWidth: CGFloat = 420
        static let helpPopoverWidth: CGFloat = 300
        static let iconTile: CGFloat = 24
        static let libraryGridIcon: CGFloat = 48
        static let libraryGridItem: CGFloat = 78
        enum LibraryPanel {
            static let maxHeight: CGFloat = 600
            static let width: CGFloat = 360
        }
        static let libraryRowIcon: CGFloat = 28
        enum LibraryTab {
            static let height: CGFloat = 64
            static let width: CGFloat = 20
        }
        static let libraryTabSymbol: CGFloat = 13
        static let menuRowHeight: CGFloat = 24
        static let menuWidth: CGFloat = 280
        static let nameFieldWidth: CGFloat = 200
        static let resolutionPopoverWidth: CGFloat = 280
        enum ResolutionWindow {
            static let barHeight: CGFloat = 72
            static let bezel: CGFloat = 5
            static let minHeight: CGFloat = 520
            static let minWidth: CGFloat = 720
            static let screenShare: CGFloat = 0.85
            static let sliderWidth: CGFloat = 440
        }
        static let rowMinHeight: CGFloat = 40
        static let settingsWidth: CGFloat = 520
        static let sheetWidth: CGFloat = 460
        static let statusTile: CGFloat = 40
        static let toggleHeight: CGFloat = 22
        static let toggleWidth: CGFloat = 38
        static let toolbarItem: CGFloat = 56
        static let zoomSliderWidth: CGFloat = 160
    }
    enum Space {
        static let l: CGFloat = 16
        static let m: CGFloat = 12
        static let s: CGFloat = 8
        static let section: CGFloat = 32
        static let xl: CGFloat = 20
        static let xs: CGFloat = 4
        static let xxl: CGFloat = 24
        static let xxs: CGFloat = 2
    }
    enum Status {
        static let problem = StatusToken(color: SwiftUI.Color(nsColor: .systemOrange), symbol: "exclamationmark.triangle.fill", text: "需要处理")
        static let reconnecting = StatusToken(color: SwiftUI.Color(nsColor: .systemOrange), symbol: "iphone.slash", text: "正在重连")
        static let remote = StatusToken(color: SwiftUI.Color(nsColor: .systemGreen), symbol: "iphone.radiowaves.left.and.right", text: "远程中")
        static let waiting = StatusToken(color: SwiftUI.Color(nsColor: .systemGray), symbol: "iphone", text: "等待连接")
    }
}

enum TouchTokens {
    enum Color {
        static let background = SwiftUI.Color(nsColor: .dynamic(light: NSColor(srgbRed: 0.949, green: 0.949, blue: 0.969, alpha: 1), dark: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)))
        static let card = SwiftUI.Color(nsColor: .dynamic(light: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1), dark: NSColor(srgbRed: 0.11, green: 0.11, blue: 0.118, alpha: 1)))
        static let danger = SwiftUI.Color(nsColor: .systemRed)
        static let fill = SwiftUI.Color(nsColor: .dynamic(light: NSColor(srgbRed: 0.463, green: 0.463, blue: 0.502, alpha: 0.12), dark: NSColor(srgbRed: 0.463, green: 0.463, blue: 0.502, alpha: 0.24)))
        static let label = SwiftUI.Color(nsColor: .dynamic(light: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1), dark: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)))
        static let secondaryLabel = SwiftUI.Color(nsColor: .dynamic(light: NSColor(srgbRed: 0.235, green: 0.235, blue: 0.263, alpha: 0.7), dark: NSColor(srgbRed: 0.922, green: 0.922, blue: 0.961, alpha: 0.7)))
        static let segment = SwiftUI.Color(nsColor: .dynamic(light: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1), dark: NSColor(srgbRed: 0.388, green: 0.388, blue: 0.4, alpha: 1)))
        static let separator = SwiftUI.Color(nsColor: .dynamic(light: NSColor(srgbRed: 0.235, green: 0.235, blue: 0.263, alpha: 0.18), dark: NSColor(srgbRed: 0.329, green: 0.329, blue: 0.345, alpha: 0.65)))
        static let tint = SwiftUI.Color(nsColor: .systemBlue)
        static let tintFill = SwiftUI.Color(nsColor: .dynamic(light: NSColor(srgbRed: 0, green: 0.533, blue: 1, alpha: 0.14), dark: NSColor(srgbRed: 0, green: 0.569, blue: 1, alpha: 0.22)))
    }
    enum Font {
        static let body = FontToken(size: 18, weight: .regular, lineHeight: 24)
        static let caption = FontToken(size: 13, weight: .regular, lineHeight: 16)
        static let headline = FontToken(size: 22, weight: .semibold, lineHeight: 28)
        static let label = FontToken(size: 15, weight: .medium, lineHeight: 20)
        static let largeTitle = FontToken(size: 40, weight: .bold, lineHeight: 48)
    }
    enum Layout {
        enum PhoneLandscape {
            static let columns: CGFloat = 2
            static let height: CGFloat = 525
            static let sidebar: CGFloat = 340
            static let width: CGFloat = 940
        }
        enum PhonePortrait {
            static let columns: CGFloat = 1
            static let height: CGFloat = 950
            static let width: CGFloat = 540
        }
        enum TabletLandscape {
            static let columns: CGFloat = 2
            static let height: CGFloat = 660
            static let sidebar: CGFloat = 360
            static let width: CGFloat = 950
        }
        enum TabletPortrait {
            static let columns: CGFloat = 1
            static let height: CGFloat = 950
            static let width: CGFloat = 660
        }
        static let tabletTopRightClear: CGFloat = 50
    }
    enum Radius {
        static let appIcon: CGFloat = 13
        static let card: CGFloat = 12
        static let control: CGFloat = 12
        static let pill: CGFloat = 999
    }
    enum Size {
        static let circleButton: CGFloat = 56
        static let gridIcon: CGFloat = 58
        enum HomeIndicator {
            static let height: CGFloat = 6
            static let hitHeight: CGFloat = 34
            static let width: CGFloat = 160
        }
        static let listIcon: CGFloat = 48
        enum Slider {
            static let thumb: CGFloat = 28
            static let track: CGFloat = 6
        }
        static let touchTarget: CGFloat = 56
    }
    enum Space {
        static let l: CGFloat = 16
        static let m: CGFloat = 12
        static let margin: CGFloat = 20
        static let s: CGFloat = 8
        static let section: CGFloat = 32
        static let xs: CGFloat = 4
        static let xxl: CGFloat = 24
        static let xxs: CGFloat = 2
    }
}

enum MotionTokens {
    static let disabledOpacity: Double = 0.4
    /// 按下、开关、小状态
    static let fast: Double = 0.15
    static let pressedOpacity: Double = 0.6
    /// 弹出表单
    static let sheet: Double = 0.25
    /// 面板切换、列表展开
    static let standard: Double = 0.2
}
