import Foundation

/// Deterministic virtual-time integration harness. It has no device or network dependencies.
public struct ScenarioSettings: Equatable, Sendable {
    public var seed: Int
    public var durationSeconds: Int
    public var headDropoutStart: Int?
    public var headDropoutDuration: Int

    public init(seed: Int = 7, durationSeconds: Int = 10,
                headDropoutStart: Int? = nil, headDropoutDuration: Int = 0) {
        self.seed = seed
        self.durationSeconds = durationSeconds
        self.headDropoutStart = headDropoutStart
        self.headDropoutDuration = headDropoutDuration
    }
}

public enum ScenarioError: Error, Equatable {
    case invalidConfiguration
}

public enum ScenarioRunner {
    /// Emits real Swift tracking and command-gate decisions, unlike waveform-only fixtures.
    public static func generate(_ config: ScenarioSettings) throws -> [SessionRecord] {
        guard (1...1800).contains(config.durationSeconds),
              (0...1800).contains(config.headDropoutDuration),
              config.headDropoutStart.map({ $0 >= 0 && $0 <= config.durationSeconds }) ?? true
        else { throw ScenarioError.invalidConfiguration }
        let session = "sim-swift-\(config.seed)"
        let base = 1000.0
        let phase = Double(config.seed % 997) / 997.0 * 2 * Double.pi
        var events: [SessionRecord] = []
        var control = HeadTrackingController()
        var gate = GimbalCommandGate()
        var monitor = SensorHealthMonitor()
        var synchronizer = SensorSynchronizer()
        var armed = true
        var mostRecentHead: HeadSample?

        func append(_ kind: String, at time: Double, fields: [String: Double] = [:],
                    note: String? = nil) {
            events.append(SessionRecord(wallTime: Date(timeIntervalSince1970: time - base),
                                        uptime: time, kind: kind, source: "simulator",
                                        fields: fields, note: note, schemaVersion: 1,
                                        sessionId: session, sequence: events.count))
        }

        append("session_start", at: base, note: "Virtual time; no aircraft connected")
        let initial = HeadSample(uptime: base, pose: HeadPose(yaw: 0, pitch: 0, roll: 0))
        control.calibrate(using: initial, currentGimbalPitch: -30)
        gate.reset()
        append("calibration", at: base, fields: ["pitch": -30])
        append("arm", at: base, note: "Simulation only")

        for step in 0..<(config.durationSeconds * 20) {
            let t = Double(step) / 20
            let now = base + t
            let drop = config.headDropoutStart.map {
                t >= Double($0) && t < Double($0 + config.headDropoutDuration)
            } ?? false
            if !drop {
                let sample = HeadSample(uptime: now,
                    pose: HeadPose(yaw: 15 * (sin(t / 4 + phase) - sin(phase)),
                                   pitch: 20 * (sin(t / 3 + phase) - sin(phase)), roll: 0))
                if monitor.observeHead(sample, receivedAt: now) == .accepted {
                    _ = synchronizer.append(sample)
                    mostRecentHead = sample
                    append("head", at: now, fields: ["yaw": sample.pose.yaw,
                        "pitch": sample.pose.pitch, "roll": 0, "sensor_uptime": now])
                }
            }
            if step % 4 == 0 {
                let aircraft = AircraftSnapshot(uptime: now, source: .simulator,
                    connected: true, flying: false, gimbalPitchDegrees: -30, batteryPercent: 85)
                if monitor.observeAircraft(aircraft, receivedAt: now) == .accepted {
                    _ = synchronizer.append(aircraft)
                    append("telemetry", at: now, fields: ["battery_percent": 85,
                        "gimbal_pitch": -30, "sensor_uptime": now])
                }
            }
            if step % 3 != 0 || !armed { continue }
            let health = monitor.health(at: now)
            guard health.head.freshness == .fresh, health.aircraft.freshness == .fresh else {
                armed = false
                gate.reset()
                append("disarm", at: now, note: "stale_input")
                continue
            }
            let aligned = synchronizer.aligned(at: now)
            let decision = control.update(sample: mostRecentHead, now: now,
                                          armed: armed, aircraftConnected: aligned.aircraft?.connected == true)
            if decision.status == .staleMotion || decision.status == .invalidInput {
                armed = false
                gate.reset()
                append("disarm", at: now, note: decision.status.rawValue)
                continue
            }
            guard let pitch = decision.pitchDegrees else { continue }
            let admission = gate.request(now: now, pitch: pitch, authorized: armed,
                connected: true, aircraftFlying: false, headTimestamp: mostRecentHead?.uptime,
                telemetryTimestamp: aligned.aircraft?.uptime)
            guard case .granted(let ticket) = admission else { continue }
            append("gimbal_command", at: now, fields: ["target_pitch": pitch,
                "head_timestamp": mostRecentHead?.uptime ?? now])
            if gate.complete(ticket, now: now + 0.005, succeeded: true) == .completed {
                append("gimbal_ack", at: now + 0.005, fields: ["command_uptime": now,
                    "target_pitch": pitch])
            }
        }
        append("session_end", at: base + Double(config.durationSeconds),
               note: "Synthetic observations")
        return events
    }
}
