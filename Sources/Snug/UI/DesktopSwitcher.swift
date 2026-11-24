import AppKit
import SnugCore
import SwiftUI

/// 电脑屏的入口与列表分别占一个小面板，点击范围之外仍由桌面窗口响应。
@MainActor
final class DesktopSwitcher: NSObject, NSWindowDelegate {
    let display: DisplayID
    private let catalog: AppCatalog
    private let intents: any TouchIntents
    private let focus: (WindowInfo) -> Void
    private let owner: String
    private var entry: TouchPanel?
    private var list: TouchPanel?
    private var panelFrame = NSRect.zero

    init(id: ScreenID, display: DisplayID, catalog: AppCatalog, intents: any TouchIntents,
         focus: @escaping (WindowInfo) -> Void) {
        self.display = display
        self.catalog = catalog
        self.intents = intents
        self.focus = focus
        owner = "desktop-switcher/\(id.rawValue)"
        super.init()

        let button = Button { [weak self] in self?.toggle() } label: {
            VStack(spacing: 6) {
                Image(systemName: "square.grid.2x2").font(.system(size: 12, weight: .medium))
                Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold))
            }
            .frame(width: 28, height: 60)
            .background(.regularMaterial, in: UnevenRoundedRectangle(bottomTrailingRadius: 12, topTrailingRadius: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("打开 App 资源库")
        .help("App 资源库")
        let panel = TouchPanel(content: FirstMouseHostingView(rootView: button), opaque: false)
        panel.level = .floating
        entry = panel
    }

    func layout(on screen: NSScreen) {
        let area = screen.visibleFrame
        let midY = area.midY
        entry?.setFrame(NSRect(x: area.minX, y: midY - 30, width: 28, height: 60), display: true)
        if entry?.isVisible == false { entry?.orderFrontRegardless() }
        let height = min(600, area.height * 0.76)
        panelFrame = NSRect(x: area.minX + 34, y: midY - height / 2,
                            width: min(340, max(1, area.width - 42)), height: height)
        list?.setFrame(panelFrame, display: true)
    }

    func close() {
        dismiss()
        entry?.close()
        entry = nil
    }

    private func toggle() {
        if list != nil { dismiss(); return }
        let view = DesktopSwitcherView(catalog: catalog, display: display, focus: { [weak self] window in
            guard let self else { return }
            dismiss()
            focus(window)
        }, move: { [weak self] window in
            guard let self else { return }
            dismiss()
            intents.pull(window)
        }, open: { [weak self] app in
            guard let self else { return }
            dismiss()
            intents.open(app)
        }, dismiss: { [weak self] in self?.dismiss() })
        let panel = TouchPanel(content: FirstMouseHostingView(rootView: view), opaque: false)
        panel.level = .floating
        panel.hasShadow = true
        panel.acceptsKeys = true
        panel.delegate = self
        list = panel
        catalog.want(owner, spots: true)
        panel.setFrame(panelFrame, display: true)
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    private func dismiss() {
        guard let panel = list else { return }
        list = nil
        panel.delegate = nil
        panel.close()
        catalog.release(owner)
    }

    func windowDidResignKey(_ notification: Notification) {
        if notification.object as? NSWindow === list { dismiss() }
    }
}

struct DesktopSwitcherView: View {
    let catalog: AppCatalog
    let display: DisplayID
    let focus: (WindowInfo) -> Void
    let move: (WindowInfo) -> Void
    let open: (AppInfo) -> Void
    let dismiss: () -> Void
    @State private var query = ""

    var body: some View {
        let groups = AppList.desktopGroups(on: display, query: query.trimmingCharacters(in: .whitespacesAndNewlines),
                                           running: catalog.running, installed: catalog.installed, spots: catalog.spots)
        VStack(alignment: .leading, spacing: 10) {
            Text("App 资源库").font(.headline)
            TextField("搜索应用或窗口", text: $query).textFieldStyle(.roundedBorder)
            if catalog.loaded {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        section("当前屏幕", empty: groups.current.isEmpty) {
                            ForEach(groups.current) { window in windowRow(window, action: "切换", run: focus) }
                        }
                        section("其他屏幕", empty: groups.other.isEmpty) {
                            ForEach(groups.other) { window in windowRow(window, action: "移到此屏", run: move) }
                        }
                        section("运行中，无窗口", empty: groups.windowless.isEmpty) {
                            ForEach(groups.windowless) { app in appRow(app, action: "重新打开") }
                        }
                        section("未打开的应用", empty: groups.unopened.isEmpty) {
                            ForEach(groups.unopened) { app in appRow(app, action: "打开") }
                        }
                        if groups.current.isEmpty && groups.other.isEmpty && groups.windowless.isEmpty && groups.unopened.isEmpty {
                            Text(query.isEmpty ? "没有可用的应用或窗口" : "没有找到应用或窗口")
                                .font(.callout).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            } else {
                ProgressView("正在读取应用和窗口")
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .onExitCommand(perform: dismiss)
    }

    @ViewBuilder private func section<Content: View>(_ title: String, empty: Bool,
                                                     @ViewBuilder content: () -> Content) -> some View {
        if !empty {
            VStack(alignment: .leading, spacing: 2) {
                Divider()
                Text(title).font(.headline).padding(.vertical, 4)
                    .accessibilityAddTraits(.isHeader)
                content()
            }
        }
    }

    private func windowRow(_ window: WindowInfo, action: String, run: @escaping (WindowInfo) -> Void) -> some View {
        let label = catalog.spots[window.key] == .fullScreen(display) ? "\(window.displayTitle) · 全屏" : window.displayTitle
        return DesktopSwitcherRow(icon: catalog.icon(for: window), title: window.app, subtitle: label,
                                  action: action) { run(window) }
    }

    private func appRow(_ app: AppInfo, action: String) -> some View {
        DesktopSwitcherRow(icon: catalog.icon(for: app), title: app.name, subtitle: nil,
                           action: action) { open(app) }
    }
}

private struct DesktopSwitcherRow: View {
    let icon: NSImage
    let title: String
    let subtitle: String?
    let action: String
    let run: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: run) {
            HStack(spacing: 8) {
                Image(nsImage: icon).resizable().frame(width: 28, height: 28).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).lineLimit(1)
                    if let subtitle { Text(subtitle).font(.callout).foregroundStyle(.secondary).lineLimit(1) }
                }
                Spacer(minLength: 8)
                Text(action).font(.callout).foregroundStyle(.secondary).fixedSize()
            }
            .padding(6)
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            .background(hovering ? MacTokens.Color.accent.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel([title, subtitle, action].compactMap { $0 }.joined(separator: "，"))
    }
}
