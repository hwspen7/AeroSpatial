import Foundation

/// A fixed-capacity ordered index for monotonic sensor timestamps.
/// Append is O(1), lookup is O(log N), and capacity is never reallocated.
public struct TimestampRing<Element: Sendable>: Sendable {
    private var elements: [Element?]
    private var head = 0
    public private(set) var count = 0
    public let capacity: Int

    public init(capacity: Int) {
        self.capacity = max(2, capacity)
        elements = Array(repeating: nil, count: self.capacity)
    }

    public var latest: Element? {
        count == 0 ? nil : self[count - 1]
    }

    public subscript(_ offset: Int) -> Element {
        precondition(offset >= 0 && offset < count)
        return elements[(head + offset) % capacity]!
    }

    public mutating func append(_ item: Element) {
        if count < capacity {
            elements[(head + count) % capacity] = item
            count += 1
        } else {
            elements[head] = item
            head = (head + 1) % capacity
        }
    }

    public mutating func removeAll() {
        elements = Array(repeating: nil, count: capacity)
        head = 0
        count = 0
    }

    /// Index of the first element whose timestamp is >= the query.
    public func lowerBound(time: Double, timestamp: (Element) -> Double) -> Int {
        var lo = 0
        var hi = count
        while lo < hi {
            let mid = lo + (hi - lo) / 2
            if timestamp(self[mid]) < time { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    /// Index of the first element whose timestamp is > the query.
    public func upperBound(time: Double, timestamp: (Element) -> Double) -> Int {
        var lo = 0
        var hi = count
        while lo < hi {
            let mid = lo + (hi - lo) / 2
            if timestamp(self[mid]) <= time { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }
}
