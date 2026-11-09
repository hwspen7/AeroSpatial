#if canImport(DJISDK)
import Foundation
import DJISDK
import AeroSpatialCore

/// DJI MSDK V4 bridge. Build and hardware verification require a Mac, a DJI App Key,
/// a supported controller and a Mavic Air 2. No aircraft flight control is implemented.
@MainActor
final class DJIAdapter: NSObject, DroneAdapter {
    let title = "DJI Mavic Air 2"
    var snapshot = AircraftSnapshot(uptime: ProcessInfo.processInfo.systemUptime,
                                    source: .dji, connected: false, flying: false)
    var onSnapshot: ((AircraftSnapshot) -> Void)?
    var onStatus: ((String) -> Void)?
    var onCapabilities: ((DeviceCapabilities) -> Void)?
    var onVideoBus: SpatialBus? {
        didSet { videoIngress?.stop(); videoIngress = onVideoBus.map(DJIVideoIngress.init(bus:)) }
    }
    private var videoIngress: DJIVideoIngress?
    private var pendingPitchCommand = false
    private var pollTimer: Timer?
    nonisolated private let flightMailbox = LatestSnapshotMailbox<AircraftSnapshot>()

    func connect() {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "DJISDKAppKey") as? String,
              !key.isEmpty, !key.contains("REPLACE_") else {
            onStatus?("DJI App Key is missing. Add the key to App/Info.plist and match the bundle ID.")
            return
        }
        onStatus?("Registering DJI SDK. Aircraft connection is not yet established.")
        DJISDKManager.registerApp(with: self)
    }

    func disconnect() {
        pollTimer?.invalidate()
        pollTimer = nil
        snapshot.connected = false
        _ = flightMailbox.takeLatest()
        onCapabilities?(.unverifiedDJI)
        videoIngress?.stop()
        pendingPitchCommand = false
        onSnapshot?(snapshot)
        // Aircraft stays under physical remote control. This does not disconnect the remote.
    }

    func setGimbalPitch(_ pitch: Double, completion: @escaping (Result<Void, Error>) -> Void) {
        guard BenchSafety.allowsExperimentalGimbal, !snapshot.flying else {
            completion(.failure(AdapterError.unavailable("Hardware pitch control requires the explicit propeller-off bench build.")))
            return
        }
        guard snapshot.connected, let aircraft = DJISDKManager.product() as? DJIAircraft,
              let gimbal = aircraft.gimbal else {
            completion(.failure(AdapterError.disconnected))
            return
        }
        guard !pendingPitchCommand else {
            completion(.failure(AdapterError.busy))
            return
        }
        pendingPitchCommand = true
        let bounded = max(-85, min(0, pitch))
        let rotation = DJIGimbalRotation.gimbalRotation(
            withPitchValue: NSNumber(value: bounded), rollValue: nil, yawValue: nil,
            time: 0.2, mode: .absoluteAngle, ignore: false)
        gimbal.rotate(with: rotation) { [weak self] error in
            Task { @MainActor [weak self] in
                self?.pendingPitchCommand = false
                if let error = error {
                    completion(.failure(error))
                    self?.onStatus?("Gimbal command rejected: \(error.localizedDescription)")
                } else {
                    completion(.success(()))
                }
            }
        }
    }

    private func refreshTelemetry() {
        let connected = (DJISDKManager.product() as? DJIAircraft)?.isConnected ?? false
        if connected != snapshot.connected {
            snapshot.connected = connected
            onSnapshot?(snapshot)
        }
        guard connected, let newest = flightMailbox.takeLatest() else { return }
        snapshot.uptime = newest.uptime
        snapshot.position = newest.position
        snapshot.altitudeMeters = newest.altitudeMeters
        snapshot.headingDegrees = newest.headingDegrees
        snapshot.flying = newest.flying
        onSnapshot?(snapshot)
    }

}

extension DJIAdapter: DJISDKManagerDelegate {
    nonisolated func appRegisteredWithError(_ error: Error?) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            if let error = error {
                self.onStatus?("DJI registration failed: \(error.localizedDescription)")
            } else {
                self.onStatus?("DJI registered. Waiting for remote controller.")
                DJISDKManager.startConnectionToProduct()
            }
        }
    }

    nonisolated func productConnected(_ product: DJIBaseProduct?) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            guard let aircraft = product as? DJIAircraft else {
                self.onStatus?("Connected device is not a DJI aircraft.")
                return
            }
            self.snapshot.connected = true
            let evidence = CapabilityEvidence(productModel: aircraft.model ?? "dji-unknown",
                connected: true, flightControllerPresent: aircraft.flightController != nil,
                cameraPresent: aircraft.camera != nil, gimbalPresent: aircraft.gimbal != nil,
                source: .dji)
            self.onCapabilities?(evidence.observedCapabilities)
            self.videoIngress?.start()
            self.onSnapshot?(self.snapshot)
            self.onStatus?("Aircraft connected. Confirm model, gimbal capability and firmware.")
            aircraft.flightController?.delegate = self
            aircraft.gimbal?.delegate = self
            aircraft.battery?.delegate = self
            self.pollTimer?.invalidate()
            self.pollTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshTelemetry() }
            }
        }
    }

    nonisolated func productDisconnected() {
        Task { @MainActor [weak self] in
            self?.disconnect()
            self?.onStatus?("Aircraft disconnected. Gimbal commands inhibited.")
        }
    }
}

extension DJIAdapter: DJIFlightControllerDelegate {
    nonisolated func flightController(_ fc: DJIFlightController, didUpdate state: DJIFlightControllerState) {
        let coordinate = state.aircraftLocation?.coordinate
        let point = coordinate.map { GeoPoint(latitude: $0.latitude, longitude: $0.longitude) }
        let altitude = Double(state.altitude)
        let heading = Double(state.attitude.yaw)
        let observation = AircraftSnapshot(uptime: ProcessInfo.processInfo.systemUptime,
            source: .dji, connected: true, flying: state.isFlying,
            position: point?.isValid == true ? point : nil,
            altitudeMeters: altitude.isFinite ? altitude : nil,
            headingDegrees: heading.isFinite ? Angle.compassDegrees(heading) : nil)
        flightMailbox.offer(observation)
    }

}

extension DJIAdapter: DJIGimbalDelegate {
    nonisolated func gimbal(_ gimbal: DJIGimbal, didUpdate state: DJIGimbalState) {
        let pitch = Double(state.attitudeInDegrees.pitch)
        Task { @MainActor [weak self] in
            self?.snapshot.gimbalPitchDegrees = pitch.isFinite ? pitch : nil
        }
    }
}

extension DJIAdapter: DJIBatteryDelegate {
    nonisolated func battery(_ battery: DJIBattery, didUpdate state: DJIBatteryState) {
        let percent = Int(state.chargeRemainingInPercent)
        Task { @MainActor [weak self] in
            self?.snapshot.batteryPercent = (0...100).contains(percent) ? percent : nil
        }
    }
}
#endif
