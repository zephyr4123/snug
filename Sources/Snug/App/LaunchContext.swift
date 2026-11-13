// 本进程的启动模式。main.swift 解析完写一次，之后只读；AppController 据此断言自己不会在只渲染的模式里被建出来
import SnugCore

enum LaunchContext {
    nonisolated(unsafe) static var mode = LaunchMode.app
}
