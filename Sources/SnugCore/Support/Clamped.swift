import Foundation

extension Comparable {
    /// 夹进范围里
    public func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}
