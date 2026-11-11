import Foundation

/// Model identities are adapter policy, not part of the generic math or transport API.
/// Exact matching deliberately avoids confusing Mavic Air 2 with DJI Air 2S.
public enum AircraftProfile: String, Codable, Sendable {
    case mavicAir2 = "Mavic Air 2"
    case air2S = "DJI Air 2S"
    case unrecognized = "Unrecognized"

    public static func identify(_ sdkModelName: String?) -> AircraftProfile {
        switch sdkModelName?.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "Mavic Air 2", "DJI Mavic Air 2": return .mavicAir2
        case "DJI Air 2S", "Air 2S": return .air2S
        default: return .unrecognized
        }
    }

    /// The experimental DJI adapter currently targets one aircraft model.
    /// A different profile needs a separate driver validation, not just a model string.
    public var isInitialBenchTarget: Bool { self == .mavicAir2 }
}
