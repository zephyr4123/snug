import CoreGraphics
import Foundation
import Testing
@testable import SnugCore

private let p0 = CGPoint(x: 100, y: 300)

private func input(_ kind: TouchInput.Kind, _ x: Double, _ y: Double, _ t: Double) -> TouchInput {
    TouchInput(kind, at: CGPoint(x: x, y: y), time: t)
}

private func scrolls(_ r: TouchResponse) -> [ScrollStep] {
    r.commands.compactMap { if case .scroll(let s) = $0 { s } else { nil } }
}

@Suite("手势翻译 TouchTranslator")
struct TouchTranslatorTests {
    @Test("参数和 iOS 一致：防抖 10 点，按住 0.5 秒算长按")
    func constants() {
        #expect(TouchTranslator.slop == 10)
        #expect(TouchTranslator.holdDuration == 0.5)
    }

    @Test("手机屏外按下：原样放行，之后的拖动、抬起也放行（原来的屏保持原版 UU 手势）")
    func outsidePassesThrough() {
        var t = TouchTranslator()
        #expect(t.handle(input(.press, 100, 300, 0), insidePhoneScreen: false) == .pass)
        #expect(t.handle(input(.drag, 160, 300, 0.1), insidePhoneScreen: false) == .pass)
        #expect(t.handle(input(.release, 160, 300, 0.2), insidePhoneScreen: false) == .pass)
    }

    @Test("点一下：按下先扣住，抬起时补发按下和抬起")
    func tap() {
        var t = TouchTranslator()
        #expect(t.handle(input(.press, 100, 300, 0), insidePhoneScreen: true) == TouchResponse(passOriginal: false, commands: []))
        // 防抖范围内的小抖动不算滑
        #expect(t.handle(input(.drag, 104, 305, 0.05), insidePhoneScreen: true) == TouchResponse(passOriginal: false, commands: []))
        #expect(t.handle(input(.release, 104, 305, 0.1), insidePhoneScreen: true)
                == TouchResponse(passOriginal: false, commands: [.replayPress, .replayCurrent]))
    }

    @Test("快速滑动：开始滚动（began 再 changed），手指往下拖内容往下走，抬起发 ended")
    func swipeScrolls() {
        var t = TouchTranslator()
        _ = t.handle(input(.press, 100, 300, 0), insidePhoneScreen: true)
        let first = t.handle(input(.drag, 100, 320, 0.05), insidePhoneScreen: true)
        #expect(first.passOriginal == false)
        let s = scrolls(first)
        #expect(s.map(\.phase) == [.began, .changed])
        #expect(s[1].pixelsY == 20)
        #expect(s[1].deltaY == 20)
        #expect(s.allSatisfy { $0.location == p0 })   // 滚的是按下处的那个列表

        let next = scrolls(t.handle(input(.drag, 100, 310, 0.06), insidePhoneScreen: true))
        #expect(next.map(\.phase) == [.changed])
        #expect(next[0].pixelsY == -10)

        let end = t.handle(input(.release, 100, 310, 0.5), insidePhoneScreen: true)
        #expect(scrolls(end).map(\.phase) == [.ended])
        #expect(!t.isCoasting)   // 停了一会儿才松手：不带惯性
    }

    @Test("滑出手机屏也跟着这一下走")
    func gestureContinuesOutside() {
        var t = TouchTranslator()
        _ = t.handle(input(.press, 100, 300, 0), insidePhoneScreen: true)
        _ = t.handle(input(.drag, 100, 340, 0.05), insidePhoneScreen: false)
        #expect(t.handle(input(.drag, 100, 380, 0.06), insidePhoneScreen: false).passOriginal == false)
    }

    @Test("慢慢拖的小数位移累计成整数像素，不会一直是 0")
    func fractionalAccumulates() {
        var t = TouchTranslator()
        _ = t.handle(input(.press, 100, 300, 0), insidePhoneScreen: true)
        _ = t.handle(input(.drag, 100, 311, 0.01), insidePhoneScreen: true)
        var total: Int32 = 0
        for i in 1...4 {
            total += scrolls(t.handle(input(.drag, 100, 311 + 0.5 * Double(i), 0.01 + 0.01 * Double(i)), insidePhoneScreen: true))[0].pixelsY
        }
        #expect(total == 2)
    }

    @Test("按住 0.5 秒再拖：补发按下和当前拖动，之后的拖动和抬起原样放行（照旧选择）")
    func holdThenDragSelects() {
        var t = TouchTranslator()
        _ = t.handle(input(.press, 100, 300, 0), insidePhoneScreen: true)
        #expect(t.handle(input(.drag, 130, 300, 0.6), insidePhoneScreen: true)
                == TouchResponse(passOriginal: false, commands: [.replayPress, .replayCurrent]))
        #expect(t.handle(input(.drag, 160, 300, 0.7), insidePhoneScreen: true) == .pass)
        #expect(t.handle(input(.release, 160, 300, 0.8), insidePhoneScreen: true) == .pass)
    }

    @Test("按住 0.5 秒不动再松手：在按下的地方点右键")
    func longPressRightClicks() {
        var t = TouchTranslator()
        _ = t.handle(input(.press, 100, 300, 0), insidePhoneScreen: true)
        #expect(t.handle(input(.release, 102, 301, 0.7), insidePhoneScreen: true)
                == TouchResponse(passOriginal: false, commands: [.rightClick(at: p0)]))
    }

    @Test("差一点 0.5 秒松手仍是点击")
    func shortHoldIsTap() {
        var t = TouchTranslator()
        _ = t.handle(input(.press, 100, 300, 0), insidePhoneScreen: true)
        #expect(t.handle(input(.release, 100, 300, 0.49), insidePhoneScreen: true).commands == [.replayPress, .replayCurrent])
    }

    @Test("甩一下：松手后带惯性，速度逐帧衰减，最后发惯性结束")
    func flingCoasts() {
        var t = TouchTranslator()
        _ = t.handle(input(.press, 100, 300, 0), insidePhoneScreen: true)
        for i in 1...5 { _ = t.handle(input(.drag, 100, 300 + 20 * Double(i), 0.02 * Double(i)), insidePhoneScreen: true) }
        _ = t.handle(input(.release, 100, 400, 0.1), insidePhoneScreen: true)
        #expect(t.isCoasting)
        var frames: [ScrollStep] = []
        while let f = t.momentumFrame() { frames.append(f) }
        #expect(!t.isCoasting)
        #expect(frames.first?.momentum == .begin)
        #expect(frames.last?.momentum == .end)
        #expect(frames.dropFirst().dropLast().allSatisfy { $0.momentum == .continue })
        #expect(frames.allSatisfy { $0.phase == .none })
        let deltas = frames.dropLast().map(\.deltaY)
        #expect(zip(deltas, deltas.dropFirst()).allSatisfy { $0 > $1 })   // 越来越慢
        #expect(deltas.first! > 0)                                        // 往下甩，接着往下走
        #expect(frames.count < 70)                                        // 一秒多一点就停
    }

    @Test("惯性中再按下：先发惯性结束，再扣住这次按下")
    func pressStopsMomentum() {
        var t = TouchTranslator()
        _ = t.handle(input(.press, 100, 300, 0), insidePhoneScreen: true)
        for i in 1...5 { _ = t.handle(input(.drag, 100, 300 + 20 * Double(i), 0.02 * Double(i)), insidePhoneScreen: true) }
        _ = t.handle(input(.release, 100, 400, 0.1), insidePhoneScreen: true)
        _ = t.momentumFrame()
        let r = t.handle(input(.press, 100, 300, 0.2), insidePhoneScreen: true)
        #expect(r.passOriginal == false)
        #expect(scrolls(r).map(\.momentum) == [.end])
        #expect(!t.isCoasting)
    }

    @Test("惯性中点一下：只是停住，不补发点击（不点到还在滚的内容）")
    func tapStopsCoastWithoutClick() {
        var t = TouchTranslator()
        _ = t.handle(input(.press, 100, 300, 0), insidePhoneScreen: true)
        for i in 1...5 { _ = t.handle(input(.drag, 100, 300 + 20 * Double(i), 0.02 * Double(i)), insidePhoneScreen: true) }
        _ = t.handle(input(.release, 100, 400, 0.1), insidePhoneScreen: true)
        _ = t.momentumFrame()
        _ = t.handle(input(.press, 100, 300, 0.2), insidePhoneScreen: true)
        let r = t.handle(input(.release, 100, 300, 0.3), insidePhoneScreen: true)
        #expect(r.passOriginal == false)
        #expect(r.commands.isEmpty)
        // 下一次普通的点照常点击
        _ = t.handle(input(.press, 100, 300, 1.0), insidePhoneScreen: true)
        #expect(t.handle(input(.release, 100, 300, 1.1), insidePhoneScreen: true).commands == [.replayPress, .replayCurrent])
    }

    @Test("事件扎堆到达（网络抖了一下）：慢慢拖不会甩出几屏，速度按更长的跨度算、并且封顶")
    func bunchedEventsDoNotOverFling() {
        var t = TouchTranslator()
        _ = t.handle(input(.press, 100, 300, 0), insidePhoneScreen: true)
        // 每 50ms 拖 5 点，很慢
        for i in 1...4 { _ = t.handle(input(.drag, 100, 300 + 5 * Double(i), 0.05 * Double(i)), insidePhoneScreen: true) }
        // 停了 120ms，3 个拖动挤在 3ms 里一起到，随即松手
        for i in 1...3 { _ = t.handle(input(.drag, 100, 320 + 5 * Double(i), 0.32 + 0.001 * Double(i)), insidePhoneScreen: true) }
        _ = t.handle(input(.release, 100, 335, 0.324), insidePhoneScreen: true)
        var total = 0.0
        while let f = t.momentumFrame() { total += f.deltaY }
        #expect(total < 200)
    }

    @Test("甩得再快，惯性速度也有上限")
    func flingSpeedCapped() {
        var t = TouchTranslator()
        _ = t.handle(input(.press, 100, 0, 0), insidePhoneScreen: true)
        for i in 1...5 { _ = t.handle(input(.drag, 100, 200 * Double(i), 0.02 * Double(i)), insidePhoneScreen: true) }
        _ = t.handle(input(.release, 100, 1000, 0.1), insidePhoneScreen: true)
        let first = t.momentumFrame()
        let cap = TouchTranslator.maxFlingSpeed / Momentum.frameRate
        #expect((first?.deltaY ?? 0) <= cap + 1)
    }
}
