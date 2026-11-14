// 设置页、「关于 Snug」共用的行标题：系统设置那样的彩色方块图标（SF Symbols）+ 标题 + 一行短说明
import SwiftUI

struct SettingLabel: View {
    let title: String
    var detail: String?
    let symbol: String
    let tint: Color

    init(_ title: String, detail: String? = nil, symbol: String, tint: Color) {
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail { Text(detail).font(.callout).foregroundStyle(.secondary) }
            }
        }
    }
}
