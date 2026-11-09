import Foundation

/// Bounded asynchronous journal sink. Admission is synchronous and does not block
/// on fsync. Writes are serialized on a dedicated worker, preserving order.
/// The journal actor owns CRC framing, rotation, truncation repair and fsync.
public final class SegmentJournalSink: @unchecked Sendable {
    public enum Failure: Error { case closed, backpressure, storageFailure(String) }
    private let journal: SegmentJournal
    private let writer = DispatchQueue(label: "aerospatial.journal.writer", qos: .utility)
    private let state = NSLock()
    private let pendingBudget: Int
    private var pendingBytes = 0
    private var closed = false
    private var errorDescription: String?

    public init(directory: URL, pendingBudgetBytes: Int = 2 * 1024 * 1024,
                segmentBytes: Int = 4 * 1024 * 1024, maximumSegments: Int = 16) throws {
        guard pendingBudgetBytes >= 1024 && pendingBudgetBytes <= 64 * 1024 * 1024 else {
            throw Failure.backpressure
        }
        journal = try SegmentJournal(directory: directory, segmentBytes: segmentBytes,
                                     maximumSegments: maximumSegments)
        pendingBudget = pendingBudgetBytes
    }

    public func submit(_ record: Data) throws {
        state.lock()
        guard !closed else { state.unlock(); throw Failure.closed }
        if let message = errorDescription {
            state.unlock()
            throw Failure.storageFailure(message)
        }
        guard !record.isEmpty, record.count <= pendingBudget - pendingBytes else {
            state.unlock()
            throw Failure.backpressure
        }
        pendingBytes += record.count
        writer.async { [self] in
            let completion = DispatchSemaphore(value: 0)
            Task.detached { [self] in
                do { try await journal.append(record) }
                catch {
                    state.lock()
                    if errorDescription == nil { errorDescription = String(describing: error) }
                    state.unlock()
                }
                completion.signal()
            }
            completion.wait()
            state.lock()
            pendingBytes -= record.count
            state.unlock()
        }
        state.unlock()
    }

    /// Drains accepted writes. Disk errors are reported rather than discarded.
    public func flush() throws {
        writer.sync { }
        state.lock()
        defer { state.unlock() }
        if let message = errorDescription { throw Failure.storageFailure(message) }
    }

    public func close() throws {
        state.lock()
        closed = true
        state.unlock()
        try flush()
    }

    public var queuedBytes: Int {
        state.lock()
        defer { state.unlock() }
        return pendingBytes
    }
}
