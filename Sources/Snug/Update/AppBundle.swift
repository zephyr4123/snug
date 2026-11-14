// 换掉正在运行的 Snug.app：核对新版本的签名，和装着的那个原子对调，退出后重新打开
import Darwin
import Foundation
import Security
import SnugCore

enum AppBundle {
    /// 新版本要满足正在运行的这份的指定要求：同一个应用标识、同一个开发者团队，签名完好。
    /// 块按 sha256 核对只防得住路上坏了，防不住被人换了；同一个开发者才防得住。
    /// 辅助功能授权也认这个指定要求，满足它，换完授权照旧有效
    static func verifySignature(of app: URL) throws {
        var running: SecCode?
        var runningStatic: SecStaticCode?
        var requirement: SecRequirement?
        var incoming: SecStaticCode?
        try check(SecCodeCopySelf([], &running))
        try check(SecCodeCopyStaticCode(running!, [], &runningStatic))
        try check(SecCodeCopyDesignatedRequirement(runningStatic!, [], &requirement))
        try check(SecStaticCodeCreateWithPath(app as CFURL, [], &incoming))
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        try check(SecStaticCodeCheckValidity(incoming!, flags, requirement))
    }

    /// 应用包 Info.plist 里的版本号。核过签名再读：Info.plist 在签名范围内，读到的才可信
    static func version(of app: URL) -> Version? {
        let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        return (info?["CFBundleShortVersionString"] as? String).flatMap(Version.init)
    }

    /// 两个目录原子对调（同一个磁盘上一步完成）：要么都换了，要么都没动
    static func swap(_ a: URL, _ b: URL) throws {
        guard renamex_np(a.path, b.path, UInt32(RENAME_SWAP)) == 0 else {
            throw AppBundleError.swap(String(cString: strerror(errno)))
        }
    }

    /// 等这个进程退出后重新打开 app。交给一个小 shell：Snug 退出后它还在，等到了就用 open 打开
    static func relaunch(_ app: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "while kill -0 \"$0\" 2>/dev/null; do sleep 0.2; done; exec /usr/bin/open \"$1\"",
                             String(getpid()), app.path]
        try process.run()
    }

    private static func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else {
            throw AppBundleError.signature(SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)")
        }
    }
}

enum AppBundleError: Error, CustomStringConvertible {
    case signature(String)
    case swap(String)

    var description: String {
        switch self {
        case .signature(let why): "签名核对没过：\(why)"
        case .swap(let why): "对调应用包失败：\(why)"
        }
    }
}
