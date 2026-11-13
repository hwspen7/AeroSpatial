import Foundation

/// Measures the received-to-decoded path without inventing a camera exposure time.
/// The timestamp must use the same host monotonic clock as the decode completion.
/// This is observation-only and never authorizes aircraft operations.
public final class DecodedFrameEvidence: @unchecked Sendable {
    public struct Snapshot: Equatable, Sendable {
        public let accepted: UInt64
        public let invalid: UInt64
        public let outOfOrder: UInt64
        public let stale: UInt64
        public let width: Int
        public let height: Int
        public let lastReceiptNanoseconds: UInt64
        public let maximumReceiptToDecodeNanoseconds: UInt64
    }

    private let lock = NSLock()
    private let maximumAgeNanoseconds: UInt64
    private var accepted: UInt64 = 0
    private var invalid: UInt64 = 0
    private var outOfOrder: UInt64 = 0
    private var stale: UInt64 = 0
    private var width: Int = 0
    private var height: Int = 0
    private var lastReceipt: UInt64 = 0
    private var maximumAge: UInt64 = 0

    public init(maximumAgeNanoseconds: UInt64 = 1_000_000_000) {
        self.maximumAgeNanoseconds = max(1, maximumAgeNanoseconds)
    }

    /// Returns true only for a bounded, monotonic, non-stale decoded frame.
    @discardableResult
    public func record(width: Int, height: Int, receivedAtNanoseconds receipt: UInt64,
                       decodedAtNanoseconds completion: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard width > 0, height > 0, width <= 8192, height <= 8192,
              receipt > 0, receipt <= completion else {
            invalid &+= 1
            return false
        }
        guard receipt >= lastReceipt else {
            outOfOrder &+= 1
            return false
        }
        let age = completion - receipt
        guard age <= maximumAgeNanoseconds else {
            stale &+= 1
            return false
        }
        accepted &+= 1
        self.width = width
        self.height = height
        lastReceipt = receipt
        maximumAge = max(maximumAge, age)
        return true
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        accepted = 0
        invalid = 0
        outOfOrder = 0
        stale = 0
        width = 0
        height = 0
        lastReceipt = 0
        maximumAge = 0
    }

    public func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(accepted: accepted, invalid: invalid,
                        outOfOrder: outOfOrder, stale: stale,
                        width: width, height: height,
                        lastReceiptNanoseconds: lastReceipt,
                        maximumReceiptToDecodeNanoseconds: maximumAge)
    }
}
