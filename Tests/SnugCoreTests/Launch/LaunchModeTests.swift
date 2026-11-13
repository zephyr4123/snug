import Foundation
import Testing
@testable import SnugCore

@Suite("启动参数 LaunchMode")
struct LaunchModeTests {
    @Test("没有参数：正常启动")
    func plain() throws {
        #expect(try LaunchMode.parse([]) == .app)
    }

    @Test("系统或 Cocoa 塞进来的单横线参数（-psn_…、-AppleLanguages …）一律忽略")
    func ignoresCocoaArguments() throws {
        #expect(try LaunchMode.parse(["-psn_0_12345"]) == .app)
        #expect(try LaunchMode.parse(["-AppleLanguages", "(zh-Hans)"]) == .app)
    }

    @Test("--watchdog")
    func watchdog() throws {
        #expect(try LaunchMode.parse(["--watchdog"]) == .watchdog)
    }

    @Test("各 --render-*：带一个输出目录；--render-tour-ui 先配图目录再输出目录")
    func renders() throws {
        let out = URL(fileURLWithPath: "/tmp/out")
        #expect(try LaunchMode.parse(["--render-settings", "/tmp/out"]) == .render(.settings, output: out))
        #expect(try LaunchMode.parse(["--render-permissions", "/tmp/out"]) == .render(.permissions, output: out))
        #expect(try LaunchMode.parse(["--render-about", "/tmp/out"]) == .render(.about, output: out))
        #expect(try LaunchMode.parse(["--render-tour", "/tmp/out"]) == .render(.tourArtwork, output: out))
        #expect(try LaunchMode.parse(["--render-legacy", "/tmp/out"]) == .render(.legacy, output: out))
        #expect(try LaunchMode.parse(["--render-tour-ui", "/tmp/img", "/tmp/out"])
                == .render(.tourSlides(images: URL(fileURLWithPath: "/tmp/img")), output: out))
    }

    @Test("缺参数值、数字写错：报错而不是悄悄用默认值启动监控")
    func errors() {
        #expect(throws: LaunchModeError.missingValue("--render-settings")) { try LaunchMode.parse(["--render-settings"]) }
        #expect(throws: LaunchModeError.missingValue("--render-tour-ui")) { try LaunchMode.parse(["--render-tour-ui", "/tmp/img"]) }
        #expect(throws: LaunchModeError.missingValue("--stress")) { try LaunchMode.parse(["--stress"]) }
        #expect(throws: LaunchModeError.invalidNumber("--stress", "abc")) { try LaunchMode.parse(["--stress", "abc"]) }
        #expect(throws: LaunchModeError.invalidNumber("--simulate", "x")) { try LaunchMode.parse(["--simulate", "iPad", "x"]) }
        #expect(throws: LaunchModeError.conflicting("--watchdog", "--dump-uu")) { try LaunchMode.parse(["--watchdog", "--dump-uu"]) }
    }

    @Test("已删掉的 --demo-authorize 和未知的双横线参数：报错")
    func removedFlags() {
        #expect(throws: LaunchModeError.unknownFlag("--demo-authorize")) { try LaunchMode.parse(["--demo-authorize"]) }
        #expect(throws: LaunchModeError.unknownFlag("--tour")) { try LaunchMode.parse(["--tour"]) }
    }

    @Test("--dump-uu、--simulate、--stress")
    func debugModes() throws {
        #expect(try LaunchMode.parse(["--dump-uu"]) == .dumpUU)
        #expect(try LaunchMode.parse(["--simulate", "iPad"]) == .simulate(names: ["iPad"], seconds: 10))
        #expect(try LaunchMode.parse(["--simulate", "iPad>iPhone", "8"]) == .simulate(names: ["iPad", "iPhone"], seconds: 8))
        #expect(try LaunchMode.parse(["--stress", "5"]) == .stress(rounds: 5, slow: false))
        #expect(try LaunchMode.parse(["--stress", "5", "--slow"]) == .stress(rounds: 5, slow: true))
    }

    @Test("只渲染的模式保证不启动监控、不碰显示器；会动显示器的只有正常启动、--simulate、--stress")
    func sideEffects() throws {
        let out = URL(fileURLWithPath: "/tmp/out")
        let renders: [LaunchMode] = [.render(.settings, output: out), .render(.permissions, output: out),
                                     .render(.about, output: out), .render(.tourArtwork, output: out),
                                     .render(.legacy, output: out),
                                     .render(.tourSlides(images: out), output: out)]
        for mode in renders {
            #expect(!mode.touchesDisplays)
        }
        #expect(!LaunchMode.dumpUU.touchesDisplays)
        #expect(LaunchMode.app.touchesDisplays)
        #expect(LaunchMode.watchdog.touchesDisplays)
        #expect(LaunchMode.simulate(names: ["iPad"], seconds: 10).touchesDisplays)
        #expect(LaunchMode.stress(rounds: 1, slow: false).touchesDisplays)
    }
}
