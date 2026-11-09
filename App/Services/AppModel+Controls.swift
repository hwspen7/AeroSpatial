import Foundation
import AeroSpatialCore

@MainActor
extension AppModel {
    func startHeadMotion() {
        guard !demoInputEnabled else {
            demoInputEnabled = false
            head = nil
            headSource = "None"
            tracking.reset()
            calibrated = false
            disarm()
            return motion.start()
        }
        motion.start()
    }

    func stopHeadMotion() {
        disarm()
        motion.stop()
        tracking.reset()
        calibrated = false
        head = nil
        spatialAwareness.reset()
        spatialCalibrated = false
        headRelativeCue = nil
        headSource = "None"
    }

    func useDemoHead() {
        guard mode == .simulation else { return }
        disarm()
        motion.stop()
        demoInputEnabled = true
        tracking.reset()
        calibrated = false
        updateDemoHead()
        show("Demo head input enabled. Commands remain within the simulator.")
    }

    func updateDemoHead() {
        guard demoInputEnabled, mode == .simulation else { return }
        let sample = HeadSample(uptime: ProcessInfo.processInfo.systemUptime,
                                pose: HeadPose(yaw: demoHeadYaw, pitch: demoHeadPitch, roll: 0))
        head = sample
        _ = synchronizer.append(sample)
        log("head", source: "simulator", fields: [
            "yaw": sample.pose.yaw, "pitch": sample.pose.pitch,
            "roll": sample.pose.roll, "sensor_uptime": sample.uptime])
        headSource = "Simulated head"
    }

    func enableLocation() { pilot.start() }

    func calibrate() {
        guard let sample = head, let pitch = aircraft.gimbalPitchDegrees else {
            show("Head motion and gimbal pitch must be available before calibration.")
            return
        }
        let age = ProcessInfo.processInfo.systemUptime - sample.uptime
        guard age >= -0.05, age <= tracking.settings.staleAfter else {
            show("Calibration requires fresh head motion.")
            return
        }
        tracking.calibrate(using: sample, currentGimbalPitch: pitch)
        calibrated = tracking.calibrated
        show(calibrated ? "Head center calibrated. Enable gimbal control explicitly." : "Calibration rejected.")
        log("calibration", source: "app", fields: ["pitch": pitch])
    }

    func arm() {
        guard aircraft.connected, calibrated, let head = head else {
            show("Connect, provide fresh head motion, and calibrate first.")
            return
        }
        guard mode != .dji || (BenchSafety.allowsExperimentalGimbal && !aircraft.flying) else {
            show("Live control is disabled outside the propeller-off developer bench build.")
            return
        }
        guard mode == .simulation ? demoInputEnabled || headMotionActive : headMotionActive && !demoInputEnabled else {
            show("Live mode requires genuine AirPods motion. Demo input is prohibited.")
            return
        }
        let headAge = ProcessInfo.processInfo.systemUptime - head.uptime
        guard headAge >= -0.05, headAge <= tracking.settings.staleAfter else {
            show("Head motion is stale. Reconnect or move the head, then calibrate again.")
            return
        }
        commandGate.reset()
        armed = true
        show(mode == .simulation ? "Simulator gimbal control enabled." :
             "Live gimbal pitch enabled. Keep the physical controller ready.")
        log("arm", source: "app", note: mode.rawValue)
    }

    func disarm() {
        guard armed else { return }
        armed = false
        commandGate.reset()
        lastDecision = .disarmed
        log("disarm", source: "app")
        show("Gimbal assistance disarmed. No further automatic commands will be sent.")
    }

    func controlTick() {
        if demoInputEnabled { updateDemoHead() }
        if mode == .dji && (aircraft.flying || !BenchSafety.allowsExperimentalGimbal) {
            if armed { disarm() }
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        if armed && commandGate.checkTimeout(now: now) {
            log("command_timeout", source: "safety", note: "Gimbal callback deadline exceeded")
            disarm()
            show("Gimbal acknowledgement timed out. Recalibrate and explicitly re-arm.")
            return
        }
        let streams = sensorHealth.health(at: now)
        headStreamQuality = streams.head
        aircraftStreamQuality = streams.aircraft
        let aligned = synchronizer.aligned(at: now)
        calculateHeadRelativeCue()
        if let advisory = advisor.checkTelemetryAge(
            lastSnapshotUptime: aircraft.connected ? aircraft.uptime : nil, now: now) {
            latestAdvisory = advisory
            log("advisory", source: "advisor",
                fields: ["related_sensor_uptime": advisory.uptime], note: advisory.code)
            if mode == .dji { audio.announce(advisory.message, key: advisory.code) }
        }
        synchronized = aligned.head != nil && aligned.aircraft?.connected == true
        let freshAircraft = aligned.aircraft?.connected == true
        if armed && commandGate.pending != nil {
            if streams.head.freshness != .fresh || streams.aircraft.freshness != .fresh {
                disarm()
                show("Safety interlock: input stream became stale during a pending command.")
            }
            return
        }
        let decision = tracking.update(sample: head, now: now, armed: armed,
                                       aircraftConnected: freshAircraft)
        lastDecision = decision.status
        if armed && [.staleMotion, .invalidInput, .disconnected].contains(decision.status) {
            disarm()
            show("Safety interlock: \(decision.status.rawValue). Recalibrate and re-arm.")
            return
        }
        guard let pitch = decision.pitchDegrees else { return }
        let admission = commandGate.request(
            now: now, pitch: pitch,
            authorized: armed && (mode == .simulation || BenchSafety.allowsExperimentalGimbal),
            connected: freshAircraft, aircraftFlying: aircraft.flying,
            headTimestamp: head?.uptime, telemetryTimestamp: aligned.aircraft?.uptime)
        guard case .granted(let ticket) = admission else {
            if case .blocked(let reason) = admission, reason != .pending {
                log("command_blocked", source: "safety", note: reason.rawValue)
                disarm()
            }
            return
        }
        let commandSource = mode.rawValue
        log("gimbal_command", source: commandSource,
            fields: ["target_pitch": pitch, "head_timestamp": head?.uptime ?? now])
        adapter.setGimbalPitch(pitch) { [weak self] result in
            guard let self = self else { return }
            let successful: Bool
            switch result {
            case .success: successful = true
            case .failure: successful = false
            }
            let completion = self.commandGate.complete(
                ticket, now: ProcessInfo.processInfo.systemUptime, succeeded: successful)
            guard completion != .ignored else { return }
            switch result {
            case .success where completion == .completed:
                self.log("gimbal_ack", source: commandSource,
                         fields: ["target_pitch": pitch, "command_uptime": now])
            default:
                let message: String
                if case .failure(let error) = result { message = error.localizedDescription }
                else { message = "Gimbal acknowledgement exceeded its deadline." }
                self.log("gimbal_error", source: commandSource,
                         fields: ["command_uptime": now], note: message)
                self.disarm()
                self.show("Gimbal control stopped: \(message)")
            }
        }
    }


}
