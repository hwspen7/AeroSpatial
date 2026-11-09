import Foundation

public enum ReplayCursorError: Error, Equatable {
    case integrityViolation(Int)
    case invalidSeek
}

/// Deterministic pull-based replay. No hardware adapter or aircraft commands.
/// Callers control the virtual clock and may seek backward freely.
public struct ReplayCursor: Sendable {
    private let records: [SessionRecord]
    private var nextIndex: Int = 0

    public init(records: [SessionRecord]) throws {
        let report = SessionIntegrity.inspect(records)
        guard report.issueCount == 0 else {
            throw ReplayCursorError.integrityViolation(report.issueCount)
        }
        self.records = records
    }

    public var count: Int { records.count }
    public var remainingCount: Int { records.count - nextIndex }
    public var nextUptime: TimeInterval? {
        nextIndex < records.count ? records[nextIndex].uptime : nil
    }

    public mutating func reset() { nextIndex = 0 }

    /// Reposition to the first record whose uptime is >= the target.
    public mutating func seek(to target: TimeInterval) throws {
        guard target.isFinite else { throw ReplayCursorError.invalidSeek }
        var low = 0
        var high = records.count
        while low < high {
            let middle = low + (high - low) / 2
            if records[middle].uptime < target { low = middle + 1 }
            else { high = middle }
        }
        nextIndex = low
    }

    /// Never emits more than maxCount records, even for large time jumps.
    public mutating func advance(through time: TimeInterval,
                                 maxCount: Int = 512) -> [SessionRecord] {
        guard time.isFinite, maxCount > 0, nextIndex < records.count else { return [] }
        let limit = min(records.count, nextIndex + min(maxCount, 10_000))
        var end = nextIndex
        while end < limit, records[end].uptime <= time { end += 1 }
        let items = Array(records[nextIndex..<end])
        nextIndex = end
        return items
    }
}
