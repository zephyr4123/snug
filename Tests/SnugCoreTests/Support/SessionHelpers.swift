import Foundation
@testable import SnugCore

/// 会话类测试的时间起点：断言里写「距 t0 的秒数」，数字能直接对上防抖、静默期这些常量
let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

/// 距 t0 多少秒
func at(_ s: Double) -> Date { t0.addingTimeInterval(s) }

/// 只有控制端表格的观测（覆盖窗口不在、推流未知）
func table(_ names: String...) -> UUSignals { UUSignals(overlayVisible: false, controllers: names, captureActive: nil) }
