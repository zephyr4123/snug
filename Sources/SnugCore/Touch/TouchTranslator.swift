// 手势翻译：手机、平板屏上，远控发来的单指操作按 iPhone 的习惯重新解释。
//   点一下          → 点击（连击计数原样保留，双击照常）；惯性滚动时点一下只是停住，不点到内容
//   单指滑动        → 滚动，松手带惯性
//   在 Codex 窗口里向右横滑 → 展开侧边栏，向左横滑 → 关闭侧边栏
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
    /// 横向滑动切换侧边栏；不是 Codex 的窗口时为 nil
    public var sidebarSwipe: SidebarSwipe?

    public init(frame: CGRect, scale: Double, closeButton: CloseButton? = nil, sidebarSwipe: SidebarSwipe? = nil) {
        self.frame = frame
        self.scale = scale
        self.closeButton = closeButton
        self.sidebarSwipe = sidebarSwipe
    }
}

/// 横向滑动到位后切换侧边栏
public struct SidebarSwipe: Equatable, Sendable {
    /// 相对按下点至少要走多远
    public var distance: CGFloat
    /// 要切换侧边栏的窗口（CGWindowID）
    public var window: UInt32

    public init(distance: CGFloat, window: UInt32) {
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
    /// 展开窗口所在 App 的侧边栏
    case showSidebar
    /// 关闭窗口所在 App 的侧边栏
    case hideSidebar
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
    /// Codex 里横向滑过这么远才切换侧边栏，避免把普通点按和小幅抖动误认成手势
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
    /// 这一次是 Codex 里可以横滑切换侧边栏的操作
    private var sidebar: SidebarSwipe?

    public init() {}

    /// 惯性还在走：调用方按 Momentum.frameRate 定时调 momentumFrame()
    public var isCoasting: Bool { momentum != nil }

    /// Codex 窗口里横向滑动切换侧边栏。不要求从系统边缘开始：iOS、UU 会优先接管贴边手势
    public static func sidebarSwipe(scale: Double, window: UInt32) -> SidebarSwipe {
        SidebarSwipe(distance: sidebarSwipeDistance * scale, window: window)
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
        sidebar = region.sidebarSwipe
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
            let dx = input.location.x - origin.x
            let dy = input.location.y - origin.y
            if let sidebar, moved < sidebar.distance {
                // 竖向明确占优时立即按滚动处理；其余先等横滑判定，避免 UU 转发首帧时斜率抖动
                if abs(dy) >= Self.slop * scale,
                   abs(dy) > abs(dx) * 1.5 {
                    phase = .scrolling
                    let began = wheel.step(dx: 0, dy: 0, phase: .began, momentum: .none, at: origin)
                    return .swallow([.scroll(began), .scroll(scrollStep(to: input))])
                }
                if abs(dx) >= Self.slop * scale || moved < Self.slop * scale {
                    return .swallow()
                }
            }
            guard moved >= Self.slop * scale else { return .swallow() }
            if input.time - since >= Self.holdDuration {
                // 按住后再拖：补发按下，接下来照旧拖动，就是原来的选择
                phase = .selecting
                return .swallow([.replayPress, .replayCurrent])
            }
            if let sidebar,
               abs(dx) >= sidebar.distance,
               abs(dy) <= abs(dx) * 0.8 {
                phase = .sidebar
                return .swallow([dx > 0 ? .showSidebar : .hideSidebar])
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
            if let sidebar,
               abs(input.location.x - origin.x) >= sidebar.distance,
               abs(input.location.y - origin.y) <= abs(input.location.x - origin.x) * 0.8 {
                return .swallow([input.location.x > origin.x ? .showSidebar : .hideSidebar])
            }
            if sidebar != nil,
               abs(input.location.x - origin.x) >= Self.slop * scale {
                // 在 Codex 里确实横拖了但没到切换距离：维持普通拖动的原行为，不补发点击
                return .swallow()
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
}
