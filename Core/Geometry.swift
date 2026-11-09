import Foundation

public enum Angle {
    /// Returns the shortest signed angle in [-180, 180).
    public static func signedDegrees(_ value: Double) -> Double {
        guard value.isFinite else { return .nan }
        let wrapped = (value + 180).truncatingRemainder(dividingBy: 360)
        return (wrapped < 0 ? wrapped + 360 : wrapped) - 180
    }

    public static func compassDegrees(_ value: Double) -> Double {
        guard value.isFinite else { return .nan }
        let wrapped = value.truncatingRemainder(dividingBy: 360)
        return wrapped < 0 ? wrapped + 360 : wrapped
    }
}

public struct RelativePosition: Equatable, Sendable {
    public var distanceMeters: Double
    public var bearingDegrees: Double
    public var relativeBearingDegrees: Double

    public init(distanceMeters: Double, bearingDegrees: Double, relativeBearingDegrees: Double) {
        self.distanceMeters = distanceMeters
        self.bearingDegrees = bearingDegrees
        self.relativeBearingDegrees = relativeBearingDegrees
    }
}

public enum Geodesy {
    public static func relativePosition(from observer: GeoPoint,
                                        to target: GeoPoint,
                                        observerHeadingDegrees: Double) -> RelativePosition? {
        guard observer.isValid, target.isValid, observerHeadingDegrees.isFinite else { return nil }
        guard let point = NativeGeometry.geodesic(from: observer, to: target) else { return nil }
        return RelativePosition(
            distanceMeters: point.distanceMeters, bearingDegrees: point.bearingDegrees,
            relativeBearingDegrees: Angle.signedDegrees(point.bearingDegrees - observerHeadingDegrees))
    }
}

public enum DirectionCue {
    /// A coarse orientation cue only. Not a substitute for visual line of sight.
    public static func label(relativeBearing: Double) -> String {
        guard relativeBearing.isFinite else { return "Direction unavailable" }
        let a = Angle.signedDegrees(relativeBearing)
        switch a {
        case -22.5..<22.5: return "Ahead"
        case 22.5..<67.5: return "Front right"
        case 67.5..<112.5: return "Right"
        case 112.5..<157.5: return "Behind right"
        case -67.5..<(-22.5): return "Front left"
        case -112.5..<(-67.5): return "Left"
        case -157.5..<(-112.5): return "Behind left"
        default: return "Behind"
        }
    }

    /// Simple stereo preview pan, not binaural HRTF or certified spatial localization.
    public static func stereoPan(relativeBearing: Double) -> Double {
        guard relativeBearing.isFinite else { return 0 }
        return NativeGeometry.pan(relativeBearingDegrees: relativeBearing) ?? 0
    }
}
