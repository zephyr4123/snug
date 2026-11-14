import Foundation

/// 可复现的伪随机字节（SplitMix64）：切块、拼包的测试要大块、没有规律、每次都一样的内容
func randomBytes(_ count: Int, seed: UInt64) -> Data {
    var state = seed
    var data = Data(count: count)
    data.withUnsafeMutableBytes { bytes in
        for i in 0..<count {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            bytes[i] = UInt8(truncatingIfNeeded: z ^ (z >> 31))
        }
    }
    return data
}
