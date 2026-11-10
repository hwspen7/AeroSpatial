import AeroSpatialNative
import Foundation

/// Best-effort, memory-bounded cross-language work queue. Not a flight-control channel.
/// A closed queue cannot be reopened. Shutdown requires quiesced producers.
public final class NativeWorkQueue: @unchecked Sendable {
    public enum Priority: UInt32, Sendable { case essential = 0, optional = 1 }
    public enum Outcome: Sendable, Equatable {
        case accepted, empty, expired, full, closed, invalid
    }
    public struct Work: Sendable, Equatable {
        public let traceID: UInt64
        public let receivedNanoseconds: UInt64
        public let deadlineNanoseconds: UInt64
        public let kind: UInt32
        public let priority: Priority
        public let payload: Data
    }
    private let pointer: OpaquePointer
    private let maximumPayload: Int

    public init?(maximumEvents: Int = 128, maximumBytes: Int = 8 * 1024 * 1024,
                 maximumPayloadBytes: Int = 2 * 1024 * 1024) {
        guard let queue = as_work_queue_create(maximumEvents, maximumBytes, maximumPayloadBytes) else {
            return nil
        }
        pointer = queue
        maximumPayload = maximumPayloadBytes
    }
    deinit { as_work_queue_destroy(pointer) }

    private static func outcome(_ result: ASWorkStatus) -> Outcome {
        switch result {
        case ASWQ_OK: return .accepted
        case ASWQ_EMPTY: return .empty
        case ASWQ_EXPIRED: return .expired
        case ASWQ_FULL: return .full
        case ASWQ_CLOSED: return .closed
        default: return .invalid
        }
    }

    public func push(_ work: Work, at nowNanoseconds: UInt64) -> Outcome {
        let header = ASWorkHeader(trace_id: work.traceID,
                                  received_ns: work.receivedNanoseconds,
                                  deadline_ns: work.deadlineNanoseconds,
                                  kind: work.kind, priority: work.priority.rawValue)
        return Self.outcome(work.payload.withUnsafeBytes { data in
            as_work_queue_push(pointer, header, data.bindMemory(to: UInt8.self).baseAddress,
                               work.payload.count, nowNanoseconds)
        })
    }

    public func pop(at nowNanoseconds: UInt64) -> Work? {
        var scratch: [UInt8] = []
        return pop(at: nowNanoseconds, reusing: &scratch)
    }

    /// Reuses a caller-owned buffer to avoid allocating a full video-sized
    /// temporary block for each queue read. Only one consumer owns scratch.
    public func pop(at nowNanoseconds: UInt64,
                    reusing scratch: inout [UInt8]) -> Work? {
        var header = ASWorkHeader()
        var length = 0
        if scratch.count < maximumPayload {
            scratch = [UInt8](repeating: 0, count: maximumPayload)
        }
        let status = scratch.withUnsafeMutableBufferPointer { buffer in
            as_work_queue_pop(pointer, nowNanoseconds, &header, buffer.baseAddress,
                              buffer.count, &length)
        }
        guard status == ASWQ_OK, let priority = Priority(rawValue: header.priority) else { return nil }
        return Work(traceID: header.trace_id, receivedNanoseconds: header.received_ns,
                    deadlineNanoseconds: header.deadline_ns, kind: header.kind,
                    priority: priority, payload: Data(scratch.prefix(length)))
    }

    public func close() { as_work_queue_close(pointer) }
    public func report() -> ASWorkStats? {
        var stats = ASWorkStats()
        return as_work_queue_stats(pointer, &stats) != 0 ? stats : nil
    }
}
