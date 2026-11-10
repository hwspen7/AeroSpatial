import SwiftUI
import AeroSpatialCore

extension DashboardView {
    var controlCard: some View {
        card("Gimbal assistance", icon: "viewfinder") {
            HStack {
                Label(model.armed ? "ARMED" : "DISARMED",
                      systemImage: model.armed ? "dot.radiowaves.left.and.right" : "hand.raised")
                    .font(.subheadline.bold())
                    .foregroundStyle(model.armed ? .orange : .secondary)
                Spacer()
                Text(model.lastDecision.rawValue).font(.caption).foregroundStyle(.secondary)
            }
            Button("Calibrate center") { model.calibrate() }
                .buttonStyle(.bordered)
            HStack {
                Button("Enable gimbal") {
                    if model.mode == .dji { confirmLiveArm = true }
                    else { model.arm() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.armed || !model.calibrated || !model.aircraft.connected ||
                          (model.mode == .dji && !model.liveBenchEnabled))
                Button("STOP", role: .destructive) { model.disarm() }
                    .buttonStyle(.bordered)
                    .disabled(!model.armed)
            }
            Toggle("Invert head pitch", isOn: $model.invertedPitch)
            HStack {
                Text("Sensitivity")
                Slider(value: $model.gain, in: 0.25...1.5)
                Text(String(format: "%.2f", model.gain)).monospacedDigit().frame(width: 44)
            }
            Text("Pitch only. Limits −85° to 0°, maximum software slew 20°/s, stale-data watchdog 400 ms. Real aircraft acceptance is hardware-dependent.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    var awarenessCard: some View {
        card("Spatial awareness", icon: "location.north.line") {
            HStack {
                metric("Distance", model.relativePosition.map { String(format: "%.0f m", $0.distanceMeters) } ?? "—")
                metric("Direction", model.relativePosition.map {
                    DirectionCue.label(relativeBearing: $0.relativeBearingDegrees)
                } ?? "—")
                metric("Heading", model.phoneHeading.map { String(format: "%.0f°", $0) } ?? "—")
            }
            Text("Direction is relative to the phone compass. This is not head-locked 3D audio or a replacement for visual observation.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Enable pilot location") { model.enableLocation() }
            Button("Calibrate head-relative direction") { model.calibrateSpatialAudio() }
                .disabled(model.head == nil || model.phoneHeading == nil)
            if let cue = model.headRelativeCue {
                Text("Head-relative preview: \(cue.approximateDirection), pan \(cue.stereoPan, specifier: "%.2f")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Alignment requires pointing both phone and head forward. This is a 2D stereo balance preview, not true 3D audio.")
                .font(.caption).foregroundStyle(.secondary)
                .buttonStyle(.bordered)
            Button("Mark camera position in recording") { model.markCameraLocation() }
                .disabled(!model.recording || !model.aircraft.connected)
            Text("A marker stores the aircraft GPS coordinate, not a geolocated object.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Voice announcements", isOn: $model.audioEnabled)
            Button("Speak approximate drone direction") { model.announceDirection() }
                .disabled(model.relativePosition == nil)
        }
    }

    var diagnosticsCard: some View {
        card("Diagnostics & safety", icon: "checkmark.shield") {
            Text("Adapter: \(model.capabilities.deviceIdentifier)")
                .font(.subheadline)
            if let head = model.headStreamQuality, let aircraft = model.aircraftStreamQuality {
                HStack(spacing: 12) {
                    metric("Head stream", head.freshness.rawValue.capitalized)
                    metric("Aircraft stream", aircraft.freshness.rawValue.capitalized)
                }
                Text("Head: \(head.accepted) accepted, \(head.rejected) rejected, \(head.observedGaps) gaps. " +
                     "Aircraft: \(aircraft.accepted) accepted, \(aircraft.rejected) rejected, \(aircraft.observedGaps) gaps.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let latency = model.controlLatency?.report(), latency.samples > 0 {
                Text("Control-loop p95 (bucket bound): \(Double(latency.p95_upper_ns) / 1_000_000, specifier: "%.2f") ms, \(latency.breaches) over budget")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let ingress = model.ingressPublisher?.snapshot() {
                Text("Sensor ingress: \(ingress.published) published, " +
                     "\(ingress.rejected) queue rejects, \(ingress.nativeRejected) bus rejects")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let video = model.videoPacketPublisher?.snapshot() {
                Text("H.264 chunks: \(video.queued) queued, \(video.overwritten) overwritten, " +
                     "\(video.rejected) rejected, \(video.forwarded) NAL units forwarded")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Device thermal level: \(ProcessInfo.processInfo.thermalState.rawValue)")
                .font(.caption).foregroundStyle(.secondary)
            Label(model.commandGate.pending == nil ? "No command in flight" : "Awaiting gimbal callback",
                  systemImage: model.commandGate.pending == nil ? "checkmark.shield" : "clock.arrow.circlepath")
                .font(.caption).foregroundStyle(.secondary)
            Text(model.mode == .simulation ?
                 "Simulator capability profile is active." :
                 "Live control is disabled by default. A developer-only propeller-off bench build is required.")
                .font(.caption).foregroundStyle(.secondary)
            if let advisory = model.latestAdvisory {
                Label(advisory.message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
            }
        }
    }

    var recordingCard: some View {
        card("Session recorder", icon: "externaldrive.badge.timemachine") {
            Text("Session data stays local. Sharing requires preparing a separate privacy-reduced log without GPS coordinates, notes, or absolute timestamps.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(model.recording ? "Stop recording" : "Start recording") {
                    if model.recording { model.stopRecording() }
                    else { model.startRecording() }
                }
                .buttonStyle(.borderedProminent)
                if model.latestSession != nil && !model.recording {
                    Button("Prepare safe export") { model.prepareSafeExport() }
                }
                if let url = model.shareableSession {
                    ShareLink(item: url) { Label("Share reduced log", systemImage: "square.and.arrow.up") }
                }
            }
        }
    }

}
