import Foundation
import Testing
@testable import SnugCore

@Suite("控制端观测：未识别不等于无人")
struct ControllerObservationTests {
    @Test("主窗口能读到但没有控制端行时，观测为未知", arguments: [
        [[String]](),
        [["我的设备", "MacBook Pro"], ["无法连接至服务器", "错误码：2003"]],
        [["远程控制", "连接时长 00:10", ""]],
    ])
    func unrecognizedRowsAreUnknown(rows: [[String]]) {
        #expect(UURemote.controllers(in: rows) == nil)
    }

    @Test("有效控制端行仍能读取，过滤其他表格、空文本、连接时长和重复名称")
    func recognizedControllers() {
        #expect(UURemote.controllers(in: [
            ["我的设备", "MacBook Pro"],
            ["", "连接时长 00:10", "iPhone", "远程控制"],
            ["iPhone", "远程控制"],
            ["iPad", "远程控制", "连接时长 00:20"],
        ]) == ["iPhone", "iPad"])
    }

    @Test("回归：未识别控制端时持续推流超过 60 秒，手机会话保持；真正停流后仍结束")
    func unrecognizedUIKeepsStreamingSession() {
        var session = RemoteSession()
        func sample(_ active: Bool) -> UUSignals {
            UUSignals(overlayVisible: false,
                      controllers: UURemote.controllers(in: []),
                      captureActive: active)
        }
        #expect(session.update(sample(true), now: at(0)) == [.began(controller: nil)])
        for seconds in [0.5, 59.5, 60, 60.5, 75.6, 300] {
            #expect(session.update(sample(true), now: at(seconds)) == [])
        }
        #expect(session.wantsPhoneScreen(now: at(300)))
        #expect(session.update(sample(false), now: at(300.5)) == [])
        #expect(session.update(sample(false), now: at(301.6)) == [.interrupted])
        #expect(session.update(sample(false), now: at(316.7)) == [.ended])
    }
}
