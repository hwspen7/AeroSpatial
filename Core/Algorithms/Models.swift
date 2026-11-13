import Foundation

public struct HeadPose: Codable, Equatable, Sendable {
    public var yaw: Double
    public var pitch: Double
    public var roll: Double

    public init(yaw: Double, pitch: Double, roll: Double) {
        self.yaw = yaw
        self.pitch = pitch
        self.roll = roll
    }

    public var isFinite: Bool {
        yaw.isFinite && pitch.isFinite && roll.isFinite
    }
}

public struct HeadSample: Codable, Equatable, Sendable {
    /// Monotonic seconds since host boot, not Unix time.
    public var uptime: TimeInterval
    public var pose: HeadPose

    public init(uptime: TimeInterval, pose: HeadPose) {
        self.uptime = uptime
        self.pose = pose
    }
}

public struct GeoPoint: Codable, Equatable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    public var isValid: Bool {
        latitude.isFinite && longitude.isFinite && abs(latitude) <= 90 && abs(longitude) <= 180
    }
}

public enum AircraftSource: String, Codable, Sendable {
    case simulator
    case dji
}

public struct AircraftSnapshot: Codable, Equatable, Sendable {
    public var uptime: TimeInterval
    public var source: AircraftSource
    public var connected: Bool
    public var flying: Bool
    public var position: GeoPoint?
    public var altitudeMeters: Double?
    public var headingDegrees: Double?
    public var gimbalPitchDegrees: Double?
    public var batteryPercent: Int?

    public init(
        uptime: TimeInterval,
        source: AircraftSource,
        connected: Bool,
        flying: Bool,
        position: GeoPoint? = nil,
        altitudeMeters: Double? = nil,
        headingDegrees: Double? = nil,
        gimbalPitchDegrees: Double? = nil,
        batteryPercent: Int? = nil
    ) {
        self.uptime = uptime
        self.source = source
        self.connected = connected
        self.flying = flying
        self.position = position
        self.altitudeMeters = altitudeMeters
        self.headingDegrees = headingDegrees
        self.gimbalPitchDegrees = gimbalPitchDegrees
        self.batteryPercent = batteryPercent
    }

    public var isValid: Bool {
        uptime.isFinite && uptime >= 0 &&
        (position?.isValid ?? true) &&
        (altitudeMeters?.isFinite ?? true) &&
        (headingDegrees?.isFinite ?? true) &&
        (gimbalPitchDegrees?.isFinite ?? true) &&
        (batteryPercent.map { (0...100).contains($0) } ?? true)
    }
}

public struct SessionRecord: Codable, Equatable, Sendable {
    public var wallTime: Date
    public var uptime: TimeInterval
    public var kind: String
    public var source: String
    public var fields: [String: Double]
    public var note: String?
    public var schemaVersion: Int?
    public var sessionId: String?
    public var sequence: Int?

    public init(wallTime: Date = Date(), uptime: TimeInterval, kind: String, source: String,
                fields: [String: Double] = [:], note: String? = nil,
                schemaVersion: Int? = nil, sessionId: String? = nil, sequence: Int? = nil) {
        self.wallTime = wallTime
        self.uptime = uptime
        self.kind = kind
        self.source = source
        self.fields = fields
        self.note = note
        self.schemaVersion = schemaVersion
        self.sessionId = sessionId
        self.sequence = sequence
    }
}
