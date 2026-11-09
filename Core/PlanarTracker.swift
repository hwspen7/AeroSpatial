import AeroSpatialNative
import Foundation

/// Position-only observations fused into a local ENU constant-velocity state.
/// The Kalman filter estimates motion; it does not control an aircraft.
public struct PlanarObservation: Equatable, Sendable {
    public let eastMeters: Double
    public let northMeters: Double
    public let seconds: Double
    public init(eastMeters: Double, northMeters: Double, seconds: Double) {
        self.eastMeters = eastMeters
        self.northMeters = northMeters
        self.seconds = seconds
    }
}

public enum PlanarUpdate: Equatable {
    case accepted
    case rejectedOutlier
    case resetAfterGap
    case invalid
}

public struct PlanarTracker {
    private var track = ASPlanarTrack()
    public init() {}
    public var isInitialized: Bool { track.initialized != 0 }
    public var eastMeters: Double { track.east.position }
    public var northMeters: Double { track.north.position }
    public var eastVelocity: Double { track.east.velocity }
    public var northVelocity: Double { track.north.velocity }
    public var positionVariance: (east: Double, north: Double) {
        (track.east.var_position, track.north.var_position)
    }

    @discardableResult
    public mutating func observe(_ observation: PlanarObservation,
                                 measurementStdMeters: Double,
                                 accelerationSpectralDensity: Double = 0.01,
                                 maximumNormalizedInnovation: Double = 16) -> PlanarUpdate {
        var nis = 0.0
        let result = as_planar_track_update(&track, observation.seconds,
                                            observation.eastMeters, observation.northMeters,
                                            measurementStdMeters, accelerationSpectralDensity,
                                            maximumNormalizedInnovation, &nis)
        switch result {
        case AS_OK: return .accepted
        case AS_OUTLIER_REJECTED: return .rejectedOutlier
        case AS_RESET_AFTER_GAP: return .resetAfterGap
        default: return .invalid
        }
    }
}
