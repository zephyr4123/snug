// 设备表：从 UU「全部设备」导入的控制端，给平板和手机填虚拟屏分辨率。
// 按行保存（修 B10）：每行的编辑先放在草稿里，这一行合法就（稍等片刻后）单独保存，不合法就地提示、只挡住这一行
import SwiftUI
import SnugCore

/// 设备表的未保存编辑。输入数字时逐字触发，等 0.8s 没有新输入再保存，免得按半截数字（例如 3840 的 384）建虚拟屏
@MainActor
@Observable
final class DeviceDrafts {
    static let typingDelay: TimeInterval = 0.8

    private(set) var rows: [String: DeviceProfile] = [:]
    private(set) var issues: [String: DeviceSizeIssue] = [:]
    var computersCollapsed = false
    var mobilesCollapsed = false
    @ObservationIgnored private var pending: [String: DispatchWorkItem] = [:]

    func value(for saved: DeviceProfile) -> DeviceProfile { rows[saved.name] ?? saved }

    /// typing：在输入框里逐字改的，延迟保存；切类型、勾高清立即保存
    func edit(_ row: DeviceProfile, saved: DeviceProfile, typing: Bool, intents: any AppIntents) {
        pending[row.name]?.cancel()
        pending[row.name] = nil
        guard row != saved else {
            rows[row.name] = nil
            issues[row.name] = nil
            return
        }
        rows[row.name] = row
        if let issue = row.sizeIssue {
            issues[row.name] = issue
            return
        }
        issues[row.name] = nil
        guard typing else { return commit(row, intents: intents) }
        let work = DispatchWorkItem { [weak self, weak intents] in
            MainActor.assumeIsolated {
                guard let self, let intents else { return }
                self.commit(row, intents: intents)
            }
        }
        pending[row.name] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.typingDelay, execute: work)
    }

    private func commit(_ row: DeviceProfile, intents: any AppIntents) {
        pending[row.name] = nil
        do {
            try intents.updateDevice(row)
            rows[row.name] = nil
        } catch let issue as DeviceSizeIssue {
            issues[row.name] = issue
        } catch {
            // 写盘失败：AppController 已在顶部提示，草稿留着，用户改下一笔时会再试
        }
    }
}

struct DeviceTable: View {
    let state: AppState
    let drafts: DeviceDrafts
    let intents: any AppIntents
    var forRender = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("控制端的分辨率").font(.headline)
                Spacer()
                if state.deviceImport == .reading { ProgressView().controlSize(.small) }
                Button("从 UU远程 导入") { intents.importDevices() }
                    .disabled(state.deviceImport == .reading)
            }
            importStatus
            Text("不知道分辨率？问 AI「<设备型号>的屏幕物理分辨率是多少」，把查到的像素数填进来，大的数填左边。")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if forRender {
                rowsView
            } else {
                ScrollView { rowsView.padding(.trailing, 8) }.frame(height: 280)
            }
        }
    }

    @ViewBuilder private var importStatus: some View {
        switch state.deviceImport {
        case .idle, .reading: EmptyView()
        case .finished(let m): Callout(symbol: "checkmark.circle.fill", text: m, tint: .green)
        case .failed(let m): Callout(symbol: "exclamationmark.circle.fill", text: m, tint: .orange)
        }
    }

    @ViewBuilder private var rowsView: some View {
        let devices = state.config.devices
        VStack(alignment: .leading, spacing: 8) {
            if devices.isEmpty {
                Callout(symbol: "tray", text: "还没有设备。在每台用来远程的手机、平板上登录同一个 UU远程 帐号，再点「从 UU远程 导入」。")
            }
            group("手机 / 平板", devices.filter { !$0.inComputerGroup },
                  collapsed: drafts.mobilesCollapsed) { drafts.mobilesCollapsed.toggle() }
            group("电脑", devices.filter(\.inComputerGroup),
                  collapsed: drafts.computersCollapsed) { drafts.computersCollapsed.toggle() }
        }
    }

    @ViewBuilder
    private func group(_ title: String, _ rows: [DeviceProfile], collapsed: Bool, toggle: @escaping () -> Void) -> some View {
        if !rows.isEmpty {
            Button(action: toggle) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.down").font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(collapsed ? -90 : 0))
                    Text(title).font(.subheadline.weight(.semibold))
                    Text("\(rows.count)").foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if !collapsed {
                ForEach(rows) { saved in
                    DeviceRow(row: drafts.value(for: saved), issue: drafts.issues[saved.name]) { new, typing in
                        drafts.edit(new, saved: saved, typing: typing, intents: intents)
                    }
                }
            }
        }
    }
}

private struct DeviceRow: View {
    let row: DeviceProfile
    let issue: DeviceSizeIssue?
    let edit: (DeviceProfile, _ typing: Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            DeviceIcon(device: row)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name).lineLimit(1)
                if let note { Text(note).font(.caption).foregroundStyle(.orange).lineLimit(1) }
            }
            .frame(width: 140, alignment: .leading)
            Picker("", selection: Binding(get: { row.kind != .computer }, set: { custom in
                var r = row
                r.kind = custom ? .guess(name: row.name, isComputerGroup: false) : .computer
                edit(r, false)
            })) {
                Text("不指定").tag(false)
                Text("自定义").tag(true)
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 140)
            if row.kind == .computer {
                Text("由 UU远程 决定，不准备虚拟屏").foregroundStyle(.secondary)
            } else {
                sizeField("宽", \.width).multilineTextAlignment(.trailing)
                Text("×")
                sizeField("高", \.height)
                Text("像素").foregroundStyle(.secondary)
                Toggle("高清", isOn: Binding(get: { row.hiDPI }, set: { var r = row; r.hiDPI = $0; edit(r, false) }))
                    .help("HiDPI：界面按一半的点数排版，文字更清楚")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(issue == nil ? Color(nsColor: .separatorColor).opacity(0.6) : .orange))
    }

    /// 这一行的就地提示：不合法的说哪里不对；还没填的提醒「填好才会准备虚拟屏」
    private var note: String? {
        if let issue { return issue.message }
        if row.kind != .computer, !row.hasSize { return "填好才会准备虚拟屏" }
        return nil
    }

    /// 0 显示为空（灰字占位）
    private func sizeField(_ placeholder: String, _ key: WritableKeyPath<DeviceProfile, Int>) -> some View {
        TextField(placeholder, value: Binding(get: { row[keyPath: key] == 0 ? nil : row[keyPath: key] },
                                              set: { var r = row; r[keyPath: key] = $0 ?? 0; edit(r, true) }),
                  format: .number.grouping(.never))
            .frame(width: 64)
    }
}
