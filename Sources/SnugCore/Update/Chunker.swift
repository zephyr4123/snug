// 按内容切块（FastCDC）：在哪里切只看那一小段内容本身，不看它在文件里的位置。
// 一个文件改了一处，只有那附近的一两块变了，前后的块原样不动；整段内容挪了位置，块也认得出来。
// 发布时把 Snug.app 切成块打进包（UpdatePackage.make），更新时把装着的那份用同样的切法切一遍，本机已有的块不再下载。
// 块按 sha256 认，切法变了不会出错：只是跨过那一版的那次更新认不出本机的块，多下载一次整包。做法和参数照 SpeakMore 的 chunker.mjs
import CryptoKit
import Foundation

public enum Chunker {
    static let minSize = 32 * 1024
    static let averageSize = 128 * 1024
    static let maxSize = 512 * 1024

    /// 每个字节值对应的随机数（gear 表），由固定的种子算出来：发布和更新、每个版本都一样
    private static let gear: [UInt32] = (0..<256).map { i in
        SHA256.hash(data: Data("snug-gear-\(i)".utf8)).prefix(4).reduce(0) { $0 << 8 | UInt32($1) }
    }

    /// 判定切点的掩码，取哈希的高位（高位受前面更多字节影响）。不到平均长度时多看一位（难切），过了平均长度少看一位（好切）
    private static let bits = Int(log2(Double(averageSize)).rounded())
    private static let strictMask = UInt32(truncatingIfNeeded: ((1 << (bits + 1)) - 1) << (31 - bits))
    private static let looseMask = UInt32(truncatingIfNeeded: ((1 << (bits - 1)) - 1) << (33 - bits))

    /// 依次的每一块在 data 里的范围（按 data 自己的下标）。空内容没有块
    public static func cuts(_ data: Data) -> [Range<Int>] {
        data.withUnsafeBytes { bytes -> [Range<Int>] in
            var cuts: [Range<Int>] = []
            var start = 0
            while start < bytes.count {
                let length = cutLength(bytes, from: start)
                cuts.append(data.startIndex + start ..< data.startIndex + start + length)
                start += length
            }
            return cuts
        }
    }

    /// 从 start 起的这一块有多长
    private static func cutLength(_ bytes: UnsafeRawBufferPointer, from start: Int) -> Int {
        let remaining = bytes.count - start
        guard remaining > minSize else { return remaining }
        let end = min(remaining, maxSize)
        let normal = min(averageSize, end)
        var hash: UInt32 = 0
        for i in minSize..<end {
            hash = (hash << 1) &+ gear[Int(bytes[start + i])]
            if hash & (i < normal ? strictMask : looseMask) == 0 { return i }
        }
        return end
    }
}

extension Data {
    /// 内容的 sha256（十六进制小写）：块、包都按它认
    var sha256: String { SHA256.hash(data: self).map { String(format: "%02x", $0) }.joined() }
}
