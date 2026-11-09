import Foundation
import AeroSpatialCore

@MainActor
extension AppModel {
    func announceDirection() {
        guard let position = relativePosition else {
            show("Location, phone heading and valid aircraft GPS are required for a direction cue.")
            return
        }
        audio.announcePosition(position)
        if !audioEnabled { show("Enable voice cues before speaking a direction.") }
    }

    func markCameraLocation() {
        let now = ProcessInfo.processInfo.systemUptime
        guard recording, aircraft.connected, let point = aircraft.position,
              now >= aircraft.uptime, now - aircraft.uptime <= 2 else {
            show("Start recording and obtain fresh aircraft GPS before marking a camera location.")
            return
        }
        log("spatial_marker", source: "app", fields: [
            "latitude": point.latitude, "longitude": point.longitude,
            "aircraft_uptime": aircraft.uptime],
            note: "Aircraft GPS position only. Not the location of the camera target.")
        show("Camera position marked in the local session recording.")
    }

    func startRecording() {
        do {
            let path = try recorder.start()
            recording = true
            log("session_start", source: "app", note: mode.rawValue)
            show("Recording to \(path.lastPathComponent)")
        } catch {
            show("Recording failed: \(error.localizedDescription)")
        }
    }

    func stopRecording() {
        guard recording else { return }
        log("session_end", source: "app")
        recording = false
        recorder.stop { [weak self] outcome in
            guard let self else { return }
            switch outcome {
            case .success(let url):
                self.latestSession = url
                self.show("Session saved. Export the JSONL log from the app.")
            case .failure(let error):
                self.show("Recording flush failed: \(error.localizedDescription)")
            }
        }
    }

    func log(_ kind: String, source: String,
             fields: [String: Double] = [:], note: String? = nil) {
        guard recording else { return }
        let record = SessionRecord(uptime: ProcessInfo.processInfo.systemUptime,
                                   kind: kind, source: source, fields: fields, note: note)
        do { try recorder.write(record) }
        catch {
            stopRecording()
            show("Recording halted after write failure: \(error.localizedDescription)")
        }
    }

    func show(_ status: String) { message = status }
}

