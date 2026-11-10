import Foundation

@MainActor
extension AppModel {
    /// Explicit user-controlled export. Never includes media, GPS, secret app
    /// keys, absolute wall time or persistent device identifiers.
    func prepareDeviceDiagnosticSummary() {
        let frame = decodedFrameEvidence.snapshot()
        let decode = videoDecoder.snapshot()
        let video = videoPacketPublisher?.snapshot()
        let clock = controlCadence?.diagnostic()
        let report: [String: Any] = [
            "schema": 1,
            "evidence_class": "device_observation_not_attestation",
            "includes_camera_capture_time": false,
            "source": mode.rawValue,
            "physical_aircraft_connected": mode == .dji && aircraft.connected,
            "headphone_motion_active": headMotionActive,
            "recording": recording,
            "armed": armed,
            "decoded_frames_accepted": frame.accepted,
            "decoded_frames_invalid": frame.invalid,
            "decoded_frames_out_of_order": frame.outOfOrder,
            "decoded_frames_stale": frame.stale,
            "decoded_width": frame.width,
            "decoded_height": frame.height,
            "host_receipt_to_decode_max_ns": frame.maximumReceiptToDecodeNanoseconds,
            "decoder_submitted": decode.submitted,
            "decoder_decoded": decode.decoded,
            "decoder_failed": decode.rejected,
            "decoder_queue_dropped": decode.queueDropped,
            "encoded_callback_admitted": video?.queued ?? 0,
            "complete_access_units": video?.accessUnits ?? 0,
            "video_queue_p95_upper_ns": video?.queueP95Nanoseconds ?? 0,
            "video_expired": video?.expired ?? 0,
            "control_delivery_p95_upper_ns": clock?.p95UpperNanoseconds ?? 0,
            "control_coalesced_ticks": clock?.missed ?? 0,
            "thermal_level": ProcessInfo.processInfo.thermalState.rawValue
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            let file = FileManager.default.temporaryDirectory
                .appendingPathComponent("aerospatial-device-diagnostics-\(UUID().uuidString).json")
            try data.write(to: file, options: .atomic)
            deviceDiagnosticsURL = file
            show("Prepared device diagnostic summary for optional sharing.")
        } catch {
            deviceDiagnosticsURL = nil
            show("Could not prepare device diagnostic summary: \(error.localizedDescription)")
        }
    }
}
