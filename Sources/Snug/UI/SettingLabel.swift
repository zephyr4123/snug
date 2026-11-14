// 设置页、「关于 Snug」共用的行标题：系统设置那样的彩色方块图标（SF Symbols）+ 标题 + 一行短说明
import SwiftUI

struct SettingLabel: View {
    let title: String
    var detail: String?
    /// 说明是要用户注意的问题：橙色、带警示图标，和正常状态区分开
    var warning = false
    let symbol: String
    let tint: Color

    init(_ title: String, detail: String? = nil, warning: Bool = false, symbol: String, tint: Color) {
        self.title = title
        self.detail = detail
        self.warning = warning
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
                if let detail, warning {
                    Label(detail, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange)
                } else if let detail {
                    Text(detail).font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }
}
