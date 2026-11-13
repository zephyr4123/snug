// 辅助功能权限在系统设置里的叫法：macOS 27 起叫「设备控制和数据访问」，更早叫「辅助功能」。
// 菜单、设置页、欢迎页都用它，用户照着字面就能在系统设置里找到
import PermissionFlow

enum PermissionName {
    static let accessibility = PermissionFlowResources.localizedString(
        for: PermissionFlowResources.accessibilityName(), localeIdentifier: "zh-Hans")
}
