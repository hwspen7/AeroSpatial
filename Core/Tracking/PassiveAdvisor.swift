import Foundation

public enum AdvisorySeverity: String, Codable, Sendable {
    case notice
    case warning
    case critical
}

public struct FlightAdvisory: Equatable, Sendable {
    public let code: String
    public let message: String
    public let severity: AdvisorySeverity
    public let uptime: TimeInterval
}

/// Read-only interpretation of observed telemetry. Produces NO flight commands.
public struct PassiveAdvisor: Sendable {
    public var warningBatteryPercent = 25
    public var criticalBatteryPercent = 15
    public var recoveryMarginPercent = 3
    public var maximumTelemetryAge: TimeInterval = 2
    private var lastConnected: Bool?
    private var lastBatteryBand = 0
    private var lastTelemetryAlert = false

    public init() {}

    public mutating func reset() {
        lastConnected = nil
        lastBatteryBand = 0
        lastTelemetryAlert = false
    }

    /// Repeated snapshots cannot re-announce a threshold without leaving that band.
    public mutating func observe(_ snapshot: AircraftSnapshot) -> [FlightAdvisory] {
        guard snapshot.uptime.isFinite else { return [] }
        var alerts: [FlightAdvisory] = []
        if lastConnected == true && !snapshot.connected {
            alerts.append(make("link_lost", "Aircraft link disconnected. Use the physical controller.",
                               .critical, snapshot.uptime))
        }
        lastConnected = snapshot.connected
        guard snapshot.connected, snapshot.flying else {
            lastBatteryBand = 0
            return alerts
        }
        guard let battery = snapshot.batteryPercent, (0...100).contains(battery) else { return alerts }
        let band: Int
        if lastBatteryBand == 2 && battery <= criticalBatteryPercent + recoveryMarginPercent {
            band = 2
        } else if lastBatteryBand >= 1 && battery <= warningBatteryPercent + recoveryMarginPercent {
            band = battery <= criticalBatteryPercent ? 2 : 1
        } else {
            band = battery <= criticalBatteryPercent ? 2 :
                   battery <= warningBatteryPercent ? 1 : 0
        }
        if band > lastBatteryBand {
            let critical = band == 2
            alerts.append(make(critical ? "battery_critical" : "battery_low",
                               critical ? "Battery is critically low. Follow aircraft return procedures." :
                                          "Battery is low. Review the aircraft return status.",
                               critical ? .critical : .warning, snapshot.uptime))
        }
        lastBatteryBand = band
        return alerts
    }

    /// Explicit watchdog evaluation; do not synthesize a fresh snapshot from a stale sample.
    public mutating func checkTelemetryAge(lastSnapshotUptime: Double?, now: Double) -> FlightAdvisory? {
        guard now.isFinite, let time = lastSnapshotUptime, time.isFinite, now >= time else { return nil }
        let stale = now - time > maximumTelemetryAge
        defer { lastTelemetryAlert = stale }
        guard stale, !lastTelemetryAlert else { return nil }
        return make("telemetry_stale", "Telemetry is stale. Do not rely on displayed flight data.",
                    .warning, now)
    }

    private func make(_ code: String, _ message: String, _ severity: AdvisorySeverity,
                      _ time: Double) -> FlightAdvisory {
        FlightAdvisory(code: code, message: message, severity: severity, uptime: time)
    }
}
