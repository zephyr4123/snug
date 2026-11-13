// UU远程 的身份。各处认 UU（感知、手势只接管它发来的操作、窗口列表里排除它）都认这里
import Foundation

public enum UURemote {
    /// UU远程 主程序
    public static let bundleID = "com.netease.uuremote"
    /// 被远程时在本机注入鼠标键盘、推流、放覆盖窗口的进程
    public static let serverProcess = "UURemoteServer"
}
