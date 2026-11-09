import Foundation
import AeroSpatialCore

@MainActor
extension AppModel {
    func safetyDecision(at now: Double, authorized: Bool) -> SafetyDecision {
        let context = SafetyContext(
            authorized: authorized, appForeground: started,
            aircraftConnected: aircraft.connected, aircraftFlying: aircraft.flying,
            headAvailable: demoInputEnabled || headMotionActive,
            headAgeSeconds: head.map { now - $0.uptime } ?? .infinity,
            telemetryAgeSeconds: now - aircraft.uptime,
            hardwarePermitted: mode == .simulation || BenchSafety.allowsExperimentalGimbal,
            commandPending: commandGate.pending != nil)
        return safetySupervisor.evaluate(context)
    }

    func updateRuntimeMetrics(durationSeconds: Double, now: Double) {
        runtimeMetrics.observe(durationSeconds: durationSeconds)
        if now - lastRuntimeUpdate >= 1 {
            lastRuntimeUpdate = now
            runtimeP95Microseconds = runtimeMetrics.upperBoundMicroseconds(percentile: 0.95)
            busPayloadBytes = spatialBus?.memoryStats()?.liveBytes
            videoOverwritten = spatialBus?.stats(for: .video)?.overwritten
            journalQueuedBytes = recorder.queuedBytes
            #if os(iOS)
            let health = MobileRuntimeHealth.sample()
            residentBytes = health.residentBytes
            thermalStatus = health.thermal
            #endif
        }
    }
}
