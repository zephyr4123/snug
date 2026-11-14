// 滚动事件的组成和惯性。字段含义对应 CGEvent 的连续滚动（触控板那种带相位的像素滚动），
// 系统层照着拼 CGEvent，App 看到的就和触控板滑动一样，列表、网页都会自己处理回弹
import CoreGraphics
import Foundation

/// kCGScrollWheelEventScrollPhase
public enum ScrollPhase: Int64, Sendable {
    case none = 0, began = 1, changed = 2, ended = 4
}

/// kCGScrollWheelEventMomentumPhase
public enum MomentumPhase: Int64, Sendable {
    case none = 0, begin = 1, `continue` = 2, end = 3
}

public struct ScrollStep: Equatable, Sendable {
    /// 整数像素（小数部分累计到下一帧，慢慢拖也不会一直是 0）
    public var pixelsX: Int32
    public var pixelsY: Int32
    /// 定点精度的原始位移
    public var deltaX: Double
    public var deltaY: Double
    public var phase: ScrollPhase
    public var momentum: MomentumPhase
    /// 滚动发生的位置：手指按下的地方（滚的是按下处的那个列表）
    public var location: CGPoint
}

/// 把小数位移累计成整数像素
struct ScrollWheel: Sendable {
    private var remainderX = 0.0
    private var remainderY = 0.0

    mutating func step(dx: Double, dy: Double, phase: ScrollPhase, momentum: MomentumPhase, at location: CGPoint) -> ScrollStep {
        remainderX += dx
        remainderY += dy
        let wholeX = remainderX.rounded(.towardZero), wholeY = remainderY.rounded(.towardZero)
        remainderX -= wholeX
        remainderY -= wholeY
        return ScrollStep(pixelsX: Int32(wholeX), pixelsY: Int32(wholeY), deltaX: dx, deltaY: dy,
                          phase: phase, momentum: momentum, location: location)
    }
}

/// 松手后的惯性：每帧速度乘一个衰减系数，慢到看不出来就停
public struct Momentum: Sendable {
    public static let frameRate = 60.0
    /// 每帧衰减（60fps 下约 0.8 秒停下）
    static let decay = 0.95
    /// 基准宽度下甩出去的速度低于这个（点/秒）就不带惯性
    static let minimumSpeed = 200.0
    /// 基准宽度下速度降到这个以下就停
    static let stopSpeed = 40.0

    private var vx: Double
    private var vy: Double
    private let stopSpeed: Double
    private var started = false

    /// 太慢的不算甩，返回 nil。scale：手机屏这一档比基准宽几倍，速度门槛跟着放大
    init?(velocity: (x: Double, y: Double), scale: Double) {
        guard hypot(velocity.x, velocity.y) > Self.minimumSpeed * scale else { return nil }
        vx = velocity.x
        vy = velocity.y
        stopSpeed = Self.stopSpeed * scale
    }

    /// 下一帧的位移；停下时返回 nil
    mutating func next() -> (dx: Double, dy: Double, phase: MomentumPhase)? {
        vx *= Self.decay
        vy *= Self.decay
        guard hypot(vx, vy) >= stopSpeed else { return nil }
        defer { started = true }
        return (vx / Self.frameRate, vy / Self.frameRate, started ? .continue : .begin)
    }
}
