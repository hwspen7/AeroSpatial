import Foundation

/// Durable framed records in actor order, decoupled from the UI thread.
/// The caller awaits append to receive a real durable write result.
public actor AsyncJournalWriter {
    private let journal: SegmentJournal
    public private(set) var written: UInt64 = 0
    public private(set) var failures: UInt64 = 0

    public init(directory: URL, segmentBytes: Int = 4 * 1024 * 1024,
                maximumSegments: Int = 16) throws {
        journal = try SegmentJournal(directory: directory, segmentBytes: segmentBytes,
                                     maximumSegments: maximumSegments)
    }

    public func append(_ bytes: Data) async throws {
        do {
            try await journal.append(bytes)
            written &+= 1
        } catch {
            failures &+= 1
            throw error
        }
    }

    public func append(record: SessionRecord) async throws {
        guard EventContract.accepts(record) else { throw SegmentJournal.Failure.invalidRecord }
        try await append(JSONEncoder().encode(record))
    }
}
