import Foundation
import AeroSpatialCore

@MainActor
extension AppModel {
    func calibrateSpatialAudio() {
        let now = ProcessInfo.processInfo.systemUptime
        guard let head = head, let heading = phoneHeading,
              let headingUptime = pilot.lastHeadingUptime,
              now - headingUptime <= 2, now - head.uptime <= 0.4,
              now >= head.uptime,
              let accuracy = pilot.headingAccuracyDegrees,
              let calibration = CompassCalibration(
                sample: head, heading: heading, headingAccuracy: accuracy) else {
            show("Spatial alignment needs fresh head motion and a compass accuracy of 20° or better.")
            return
        }
        spatialAwareness.setCalibration(calibration)
        spatialCalibrated = true
        calculateHeadRelativeCue()
        log("spatial_alignment", source: "app", fields: [
            "head_yaw": head.pose.yaw, "phone_heading": heading, "heading_accuracy": accuracy])
        show("Audio alignment set. Keep head and phone pointed forward together during calibration.")
    }

    func calculateHeadRelativeCue() {
        guard let head = head, let pilotFix = location, let target = aircraft.position,
              let pilotUptime = pilot.lastPositionUptime else {
            headRelativeCue = nil
            return
        }
        headRelativeCue = spatialAwareness.cue(
            head: head, now: ProcessInfo.processInfo.systemUptime,
            pilot: pilotFix, pilotFixUptime: pilotUptime,
            target: target, targetFixUptime: aircraft.uptime)
    }

    func calculateRelativePosition() {
        guard let location = location, let target = aircraft.position,
              let heading = phoneHeading, aircraft.connected else {
            relativePosition = nil
            return
        }
        // Relative to the phone compass, not gaze. Absolute AirPods yaw is not geographic heading.
        relativePosition = Geodesy.relativePosition(from: location, to: target,
                                                     observerHeadingDegrees: heading)
    }

}
