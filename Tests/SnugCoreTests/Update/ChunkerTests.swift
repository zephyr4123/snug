import Foundation
import Testing
@testable import SnugCore

@Suite("按内容切块 Chunker")
struct ChunkerTests {
    @Test("空内容没有块；不到最小块长的整个是一块")
    func small() {
        #expect(Chunker.cuts(Data()) == [])
        #expect(Chunker.cuts(randomBytes(1000, seed: 1)) == [0..<1000])
    }

    @Test("块首尾相接盖满全部内容；除了最后一块，长度都在最小和最大之间；同样的内容切法一样")
    func covers() {
        let data = randomBytes(3_000_000, seed: 2)
        let cuts = Chunker.cuts(data)
        #expect(cuts.first?.lowerBound == 0)
        #expect(cuts.last?.upperBound == data.count)
        for (a, b) in zip(cuts, cuts.dropFirst()) { #expect(a.upperBound == b.lowerBound) }
        for cut in cuts.dropLast() { #expect((Chunker.minSize...Chunker.maxSize).contains(cut.count)) }
        #expect(cuts.count > 10)
        #expect(Chunker.cuts(data) == cuts)
    }

    @Test("切点只看内容：前面插进一段，后面的块原样认得出来")
    func contentDefined() {
        let data = randomBytes(3_000_000, seed: 3)
        let shifted = randomBytes(5000, seed: 4) + data
        let before = Set(Chunker.cuts(data).map { data[$0].sha256 })
        let after = Chunker.cuts(shifted).map { shifted[$0].sha256 }
        #expect(after.filter(before.contains).count >= after.count - 2)
    }

    @Test("切的是 Data 切片时，范围按切片自己的下标给")
    func slices() {
        let whole = randomBytes(600_000, seed: 5)
        let slice = whole[100_000...]
        let cuts = Chunker.cuts(slice)
        #expect(cuts.first?.lowerBound == 100_000)
        #expect(cuts.map { slice[$0].sha256 } == Chunker.cuts(Data(slice)).map { Data(slice)[$0].sha256 })
    }
}
