import Foundation

/// Coarse bounded alignment of independently clocked sensor streams.
/// Aircraft coordinates are not interpolated and future telemetry is never used.
public struct AlignedObservation: Sendable, Equatable {
    public let uptime: TimeInterval
    public let head: HeadPose?
    public let aircraft: AircraftSnapshot?
    public let interpolatedHead: Bool

    public init(uptime: TimeInterval, head: HeadPose?, aircraft: AircraftSnapshot?,
                interpolatedHead: Bool) {
        self.uptime = uptime
        self.head = head
        self.aircraft = aircraft
        self.interpolatedHead = interpolatedHead
    }
}

public struct SensorSynchronizer: Sendable {
    public let capacity: Int
    public var maximumHeadOffset: TimeInterval
    public var maximumAircraftAge: TimeInterval
    private var headBuffer: TimestampRing<HeadSample>
    private var aircraftBuffer: TimestampRing<AircraftSnapshot>

    public init(capacity: Int = 256, maximumHeadOffset: Double = 0.4,
                maximumAircraftAge: Double = 2.0) {
        let boundedCapacity = max(2, min(65536, capacity))
        self.capacity = boundedCapacity
        self.maximumHeadOffset = max(0, maximumHeadOffset)
        self.maximumAircraftAge = max(0, maximumAircraftAge)
        headBuffer = TimestampRing(capacity: boundedCapacity)
        aircraftBuffer = TimestampRing(capacity: boundedCapacity)
    }

    @discardableResult
    public mutating func append(_ sample: HeadSample) -> Bool {
        guard sample.uptime.isFinite, sample.pose.isFinite,
              (headBuffer.latest?.uptime ?? -.infinity) <= sample.uptime else { return false }
        headBuffer.append(sample)
        return true
    }

    @discardableResult
    public mutating func append(_ snapshot: AircraftSnapshot) -> Bool {
        guard snapshot.isValid,
              (aircraftBuffer.latest?.uptime ?? -.infinity) <= snapshot.uptime else { return false }
        aircraftBuffer.append(snapshot)
        return true
    }

    public mutating func reset() {
        headBuffer.removeAll()
        aircraftBuffer.removeAll()
    }

    public func aligned(at time: TimeInterval) -> AlignedObservation {
        guard time.isFinite else {
            return AlignedObservation(uptime: time, head: nil, aircraft: nil, interpolatedHead: false)
        }
        let lower = headBuffer.lowerBound(time: time) { $0.uptime }
        let upper = headBuffer.upperBound(time: time) { $0.uptime }
        let before = upper > 0 ? headBuffer[upper - 1] : nil
        let after = lower < headBuffer.count ? headBuffer[lower] : nil
        var head: HeadPose?
        var interpolated = false

        if let before, let after,
           before.uptime != after.uptime,
           time - before.uptime <= maximumHeadOffset,
           after.uptime - time <= maximumHeadOffset {
            let ratio = (time - before.uptime) / (after.uptime - before.uptime)
            let from = before.pose
            let to = after.pose
            head = HeadPose(
                yaw: Angle.signedDegrees(from.yaw + Angle.signedDegrees(to.yaw - from.yaw) * ratio),
                pitch: Angle.signedDegrees(from.pitch + Angle.signedDegrees(to.pitch - from.pitch) * ratio),
                roll: Angle.signedDegrees(from.roll + Angle.signedDegrees(to.roll - from.roll) * ratio))
            interpolated = true
        } else if let before, time - before.uptime <= maximumHeadOffset {
            head = before.pose
        } else if let after, after.uptime - time <= maximumHeadOffset {
            head = after.pose
        }
        let upperAircraft = aircraftBuffer.upperBound(time: time) { $0.uptime }
        let candidate = upperAircraft > 0 ? aircraftBuffer[upperAircraft - 1] : nil
        let aircraft = candidate.flatMap { time - $0.uptime <= maximumAircraftAge ? $0 : nil }
        return AlignedObservation(uptime: time, head: head,
                                  aircraft: aircraft, interpolatedHead: interpolated)
    }
}
