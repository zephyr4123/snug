// 手势翻译：手机、平板屏上，远控发来的单指操作按 iPhone 的习惯重新解释。
//   点一下          → 点击（连击计数原样保留，双击照常）；惯性滚动时点一下只是停住，不点到内容
//   单指滑动        → 滚动，松手带惯性
//   在 Codex 窗口左缘右滑 → 展开侧边栏，在右缘左滑 → 关闭侧边栏
//   按住 0.5 秒再拖 → 选择（照旧拖动）
//   按住 0.5 秒松手 → 右键菜单（选区不丢，菜单里有拷贝、粘贴）
//   点窗口自己的关闭按钮 → 不补发点击，交给 Snug 先把窗口放回原位再关（直接关，App 会存下屏上的大小和字号）
// 远控把单指拖动当成鼠标拖动发过来（会选中文字；UU 实测，RustDesk 源码同样），滚动要两根手指，这里在 Mac 这一侧翻译回来。
// 纯状态机：吃进远控的按下 / 拖动 / 抬起，吐出「原事件放不放行」和要补发的事件，时间由调用方给。
// 只有范围（TouchRegion）里按下的那一下会被接管；之后的拖动、抬起跟着这一下走，手指滑出范围也一样。
// 阈值按基准宽度标定，乘上范围带来的缩放倍数：屏换到更宽的一档时跟着放大，在手机上手感不变。
// 这个模块不认屏：范围和倍数由调用方给（TouchRegion(screen:closeButton:)），系统那半在 SnugSystem 的 TouchTap
import CoreGraphics
import Foundation

/// 手势翻译管的范围（全局坐标），和这块范围比基准宽度宽几倍：阈值都乘它
public struct TouchRegion: Equatable, Sendable {
    public var frame: CGRect
    public var scale: Double
    /// 屏上那个窗口的关闭按钮；露着列表、没放窗口时为 nil
    public var closeButton: CloseButton?
    /// 两侧边缘切换侧边栏的范围；不是 Codex 的窗口时为 nil
    public var sidebarSwipe: SidebarSwipe?

    public init(frame: CGRect, scale: Double, closeButton: CloseButton? = nil, sidebarSwipe: SidebarSwipe? = nil) {
        self.frame = frame
        self.scale = scale
        self.closeButton = closeButton
        self.sidebarSwipe = sidebarSwipe
    }
}

/// 在窗口左缘向右滑展开侧边栏、在右缘向左滑关闭侧边栏
public struct SidebarSwipe: Equatable, Sendable {
    /// 能开始展开手势的左缘（全局坐标）
    public var leftEdge: CGRect
    /// 能开始关闭手势的右缘（全局坐标）
    public var rightEdge: CGRect
    /// 相对按下点至少要走多远
    public var distance: CGFloat
    /// 要切换侧边栏的窗口（CGWindowID）
    public var window: UInt32

    public init(leftEdge: CGRect, rightEdge: CGRect, distance: CGFloat, window: UInt32) {
        self.leftEdge = leftEdge
        self.rightEdge = rightEdge
        self.distance = distance
        self.window = window
    }
}

/// 屏上那个窗口的关闭按钮：铺好时读的位置，和当时窗口的编号、位置。
/// 位置是缓存的，点下去时要用窗口服务器再核对一次（isFrontmost）：窗口可能已经被拖走、被别的窗口盖住或进了全屏
public struct CloseButton: Equatable, Sendable {
    /// 按钮的位置（全局坐标，左上原点）
    public var frame: CGRect
    /// 窗口的系统编号（CGWindowID）
    public var window: UInt32
    /// 读按钮时窗口的位置
    public var windowFrame: CGRect

    public init(frame: CGRect, window: UInt32, windowFrame: CGRect) {
        self.frame = frame
        self.window = window
        self.windowFrame = windowFrame
    }

    /// 这一点上最上面的窗口还是它、而且还在读按钮时的位置。onScreen：窗口服务器给的屏上窗口，从前到后
    public func isFrontmost(at point: CGPoint, onScreen: [(id: UInt32, frame: CGRect)]) -> Bool {
        guard frame.contains(point), let top = onScreen.first(where: { $0.frame.contains(point) }) else { return false }
        return top.id == window && top.frame.matches(windowFrame)
    }
}

public struct TouchInput: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case press, drag, release }

    public var kind: Kind
    public var location: CGPoint
    /// 单调时间（秒）
    public var time: TimeInterval

    public init(_ kind: Kind, at location: CGPoint, time: TimeInterval) {
        self.kind = kind
        self.location = location
        self.time = time
    }
}

public enum TouchCommand: Equatable, Sendable {
    /// 补发扣住的那次按下
    case replayPress
    /// 补发当前这个事件（原事件吞掉，保证顺序在补发的按下之后）
    case replayCurrent
    case rightClick(at: CGPoint)
    case scroll(ScrollStep)
    /// 切换窗口所在 App 的侧边栏
    case toggleSidebar
    /// 点了窗口的关闭按钮：原来的按下、抬起先扣着。系统那半核对过按钮还在那里就交给 Snug 先放回原位再关，
    /// 对不上（窗口挪走、被盖住）就照常补发这次点击
    case closeWindow(at: CGPoint)
}

public struct TouchResponse: Equatable, Sendable {
    public var passOriginal: Bool
    public var commands: [TouchCommand]

    public static let pass = TouchResponse(passOriginal: true, commands: [])
    static func swallow(_ commands: [TouchCommand] = []) -> TouchResponse {
        TouchResponse(passOriginal: false, commands: commands)
    }
}

public struct TouchTranslator: Sendable {
    /// 基准宽度下移动不到这么多点算没动（约合手机上 8 点）
    public static let slop = 10.0
    /// 左缘右滑要走过这么远才切换侧边栏，避免把从边缘开始的普通横滑误认成手势
    public static let sidebarSwipeDistance = 32.0
    /// 按住这么久算长按，和 iOS 一样
    public static let holdDuration: TimeInterval = 0.5
    /// 用松手前这段时间的位移估算甩出去的速度
    static let flingWindow: TimeInterval = 0.1
    /// 估速的样本至少跨这么久：事件经网络转发，会几个挤在几毫秒里一起到，跨度太短算出来的速度是假的
    static let minFlingSpan: TimeInterval = 0.04
    /// 基准宽度下甩出去的速度上限（点/秒）：约滚一千多点就停
    static let maxFlingSpeed = 4000.0

    private enum Phase: Equatable {
        case idle
        /// 按下了，还看不出是点、滑还是长按（按下事件先扣着）
        case pending(since: TimeInterval)
        case scrolling
        case sidebar
        case selecting
    }

    private enum SidebarEdge: Equatable {
        case left
        case right
    }

    private struct SidebarGesture: Equatable {
        var edge: SidebarEdge
        var distance: CGFloat
        var window: UInt32
    }

    private var phase = Phase.idle
    private var origin = CGPoint.zero
    private var last = CGPoint.zero
    private var samples: [(time: TimeInterval, point: CGPoint)] = []
    private var wheel = ScrollWheel()
    private var momentum: Momentum?
    /// 这次按下时范围比基准宽几倍：阈值都乘它
    private var scale = 1.0
    /// 这次按下停掉了惯性：很快松手就只是停住，不补发点击
    private var pressStoppedCoast = false
    /// 这次按在窗口的关闭按钮上
    private var pressOnClose = false
    /// 这次按在哪一侧的侧边栏手势边缘
    private var sidebar: SidebarGesture?

    public init() {}

    /// 惯性还在走：调用方按 Momentum.frameRate 定时调 momentumFrame()
    public var isCoasting: Bool { momentum != nil }

    /// Codex 窗口左缘向右滑展开侧边栏，右缘向左滑关闭
    public static func sidebarSwipe(from frame: CGRect, scale: Double, window: UInt32) -> SidebarSwipe {
        let edgeWidth = slop * scale
        return SidebarSwipe(leftEdge: CGRect(x: frame.minX, y: frame.minY, width: edgeWidth, height: frame.height),
                            rightEdge: CGRect(x: frame.maxX - edgeWidth, y: frame.minY, width: edgeWidth, height: frame.height),
                            distance: sidebarSwipeDistance * scale, window: window)
    }

    /// region：手势翻译管的范围（关掉时为 nil）。只看按下那一下落没落在里面
    public mutating func handle(_ input: TouchInput, in region: TouchRegion?) -> TouchResponse {
        switch input.kind {
        case .press: press(input, in: region)
        case .drag: drag(input)
        case .release: release(input)
        }
    }

    /// 惯性的下一帧；惯性结束的那一帧之后返回 nil
    public mutating func momentumFrame() -> ScrollStep? {
        guard var m = momentum else { return nil }
        guard let frame = m.next() else {
            momentum = nil
            return wheel.step(dx: 0, dy: 0, phase: .none, momentum: .end, at: origin)
        }
        momentum = m
        return wheel.step(dx: frame.dx, dy: frame.dy, phase: .none, momentum: frame.phase, at: origin)
    }

    private mutating func press(_ input: TouchInput, in region: TouchRegion?) -> TouchResponse {
        // 新的一按先把还在走的惯性停掉（和 iPhone 上手指按住正在滚的列表一样）
        let stop = stopMomentum()
        guard let region, region.frame.contains(input.location) else {
            phase = .idle
            return TouchResponse(passOriginal: true, commands: stop)
        }
        scale = region.scale
        pressStoppedCoast = !stop.isEmpty
        pressOnClose = region.closeButton?.frame.contains(input.location) ?? false
        sidebar = region.sidebarSwipe.flatMap { swipe -> SidebarGesture? in
            if swipe.leftEdge.contains(input.location) {
                return SidebarGesture(edge: .left, distance: swipe.distance, window: swipe.window)
            }
            if swipe.rightEdge.contains(input.location) {
                return SidebarGesture(edge: .right, distance: swipe.distance, window: swipe.window)
            }
            return nil
        }
        phase = .pending(since: input.time)
        origin = input.location
        last = input.location
        samples = [(input.time, input.location)]
        wheel = ScrollWheel()
        return .swallow(stop)
    }

    private mutating func drag(_ input: TouchInput) -> TouchResponse {
        switch phase {
        case .idle, .selecting:
            return .pass
        case .pending(let since):
            let moved = distance(input.location, origin)
            if let sidebar, moved < sidebar.distance {
                if sidebarProgress(input.location, for: sidebar) != nil {
                    // 边缘滑动的判定距离内：先扣着，不能先滚一下再切换
                    return .swallow()
                }
                if moved < Self.slop * scale { return .swallow() }
            }
            guard moved >= Self.slop * scale else { return .swallow() }
            if input.time - since >= Self.holdDuration {
                // 按住后再拖：补发按下，接下来照旧拖动，就是原来的选择
                phase = .selecting
                return .swallow([.replayPress, .replayCurrent])
            }
            if let sidebar, let progress = sidebarProgress(input.location, for: sidebar) {
                if progress >= sidebar.distance {
                    phase = .sidebar
                    return .swallow([.toggleSidebar])
                }
                // 还在边缘滑动的判定距离内：先扣着，不能先滚一下再切换
                return .swallow()
            }
            phase = .scrolling
            let began = wheel.step(dx: 0, dy: 0, phase: .began, momentum: .none, at: origin)
            return .swallow([.scroll(began), .scroll(scrollStep(to: input))])
        case .scrolling:
            return .swallow([.scroll(scrollStep(to: input))])
        case .sidebar:
            return .swallow()
        }
    }

    private mutating func release(_ input: TouchInput) -> TouchResponse {
        switch phase {
        case .idle, .selecting:
            phase = .idle
            return .pass
        case .pending(let since):
            phase = .idle
            if input.time - since >= Self.holdDuration {
                return .swallow([.rightClick(at: origin)])
            }
            if let sidebar, let progress = sidebarProgress(input.location, for: sidebar) {
                if progress >= sidebar.distance {
                    return .swallow([.toggleSidebar])
                }
                if progress >= Self.slop * scale {
                    // 在边缘确实沿正确方向拖了，但没到切换距离：维持普通拖动的原行为，不补发点击
                    return .swallow()
                }
            }
            // iPhone 上点一下正在滚的列表只是停住；补发点击会点到手指下还在移动的东西
            if pressStoppedCoast { return .swallow() }
            return pressOnClose ? .swallow([.closeWindow(at: origin)]) : .swallow([.replayPress, .replayCurrent])
        case .scrolling:
            phase = .idle
            let ended = wheel.step(dx: 0, dy: 0, phase: .ended, momentum: .none, at: origin)
            momentum = Momentum(velocity: flingVelocity(at: input.time), scale: scale)
            return .swallow([.scroll(ended)])
        case .sidebar:
            phase = .idle
            return .swallow()
        }
    }

    /// 手指往下拖，内容跟着往下走（和 iPhone 一样）
    private mutating func scrollStep(to input: TouchInput) -> ScrollStep {
        let dx = Double(input.location.x - last.x), dy = Double(input.location.y - last.y)
        last = input.location
        samples.append((input.time, input.location))
        if samples.count > 30 { samples.removeFirst(samples.count - 30) }
        return wheel.step(dx: dx, dy: dy, phase: .changed, momentum: .none, at: origin)
    }

    private mutating func stopMomentum() -> [TouchCommand] {
        guard momentum != nil else { return [] }
        momentum = nil
        return [.scroll(wheel.step(dx: 0, dy: 0, phase: .none, momentum: .end, at: origin))]
    }

    /// 松手前 flingWindow 内的平均速度（点/秒）。松手前停住了（窗口里不到两个样本）就不甩。
    /// 样本跨度不到 minFlingSpan 时往前多取，再封顶（按这一档放大的）maxFlingSpeed
    private func flingVelocity(at time: TimeInterval) -> (x: Double, y: Double) {
        let recent = samples.filter { time - $0.time <= Self.flingWindow }
        guard var a = recent.first, let b = recent.last, b.time > a.time else { return (0, 0) }
        if b.time - a.time < Self.minFlingSpan {
            a = samples.last { b.time - $0.time >= Self.minFlingSpan } ?? samples[0]
        }
        let dt = b.time - a.time
        let v = (x: Double(b.point.x - a.point.x) / dt, y: Double(b.point.y - a.point.y) / dt)
        let speed = hypot(v.x, v.y), cap = Self.maxFlingSpeed * scale
        guard speed > cap else { return v }
        return (v.x / speed * cap, v.y / speed * cap)
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> Double { hypot(Double(a.x - b.x), Double(a.y - b.y)) }

    /// 沿正确边缘方向、以横向为主的位移；方向不对或纵向占优时返回 nil
    private func sidebarProgress(_ point: CGPoint, for gesture: SidebarGesture) -> CGFloat? {
        let dx = point.x - origin.x
        let dy = point.y - origin.y
        let progress = gesture.edge == .left ? dx : -dx
        guard progress > 0, abs(dy) < progress else { return nil }
        return progress
    }
}
