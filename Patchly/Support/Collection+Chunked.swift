import Foundation

extension Array {
    /// Splits into consecutive chunks of at most `size` elements — used to
    /// bound concurrent network fetches in the feed-based Update Sources.
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
