import Foundation

/// Immutable, explicitly clock-scoped device calibration. The transform maps child to parent.
public struct TimedFrameCalibration: Sendable, Equatable {
    public let identifier: String
    public let parent: FrameIdentifier
    public let child: FrameIdentifier
    public let transform: SpatialTransform
    public let validFromNanoseconds: UInt64
    public let validUntilNanoseconds: UInt64
    public let clockDomain: UInt32

    public init?(identifier: String, parent: FrameIdentifier, child: FrameIdentifier,
                 transform: SpatialTransform, validFromNanoseconds: UInt64,
                 validUntilNanoseconds: UInt64, clockDomain: UInt32) {
        let numeric = [transform.translation.east, transform.translation.north,
                       transform.translation.up, transform.rotation.w,
                       transform.rotation.x, transform.rotation.y, transform.rotation.z]
        let norm = transform.rotation.w * transform.rotation.w +
                   transform.rotation.x * transform.rotation.x +
                   transform.rotation.y * transform.rotation.y +
                   transform.rotation.z * transform.rotation.z
        guard (3...64).contains(identifier.count),
              identifier.utf8.allSatisfy({ ($0 >= 48 && $0 <= 57) ||
                                          ($0 >= 65 && $0 <= 90) ||
                                          ($0 >= 97 && $0 <= 122) || $0 == 95 || $0 == 45 }),
              parent != child, clockDomain > 0,
              validFromNanoseconds < validUntilNanoseconds,
              numeric.allSatisfy(\.isFinite), abs(norm - 1.0) < 0.0001 else { return nil }
        self.identifier = identifier
        self.parent = parent
        self.child = child
        self.transform = transform
        self.validFromNanoseconds = validFromNanoseconds
        self.validUntilNanoseconds = validUntilNanoseconds
        self.clockDomain = clockDomain
    }
}

/// Metadata-only lookups. Fail closed on unknown clock domain, calibration gaps,
/// uncertainty spanning a revision boundary or ambiguous alternative paths.
public struct TimedFrameGraph: Sendable {
    private var revisions: [TimedFrameCalibration] = []
    public init() {}

    public mutating func add(_ calibration: TimedFrameCalibration) -> Bool {
        guard revisions.count < 256,
              !revisions.contains(where: { $0.identifier == calibration.identifier }),
              !revisions.contains(where: { current in
                  current.clockDomain == calibration.clockDomain &&
                  ((current.parent == calibration.parent && current.child == calibration.child) ||
                   (current.parent == calibration.child && current.child == calibration.parent)) &&
                  current.validFromNanoseconds < calibration.validUntilNanoseconds &&
                  calibration.validFromNanoseconds < current.validUntilNanoseconds
              }) else { return false }
        revisions.append(calibration)
        return true
    }

    public func resolve(from child: FrameIdentifier, to parent: FrameIdentifier,
                        at timeNanoseconds: UInt64, uncertaintyNanoseconds: UInt64,
                        clockDomain: UInt32) -> SpatialTransform? {
        guard clockDomain > 0, uncertaintyNanoseconds <= timeNanoseconds,
              timeNanoseconds <= UInt64.max - uncertaintyNanoseconds else { return nil }
        let low = timeNanoseconds - uncertaintyNanoseconds
        let high = timeNanoseconds + uncertaintyNanoseconds
        var graph = FrameGraph()
        for calibration in revisions where calibration.clockDomain == clockDomain &&
            calibration.validFromNanoseconds <= low && high < calibration.validUntilNanoseconds {
            guard graph.link(parent: calibration.parent, child: calibration.child,
                             transform: calibration.transform) else { return nil }
        }
        return graph.resolve(from: child, to: parent)
    }
}
