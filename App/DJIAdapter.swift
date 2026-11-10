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
    private var pendingPitchCommand = false
    private var pollTimer: Timer?
    private var videoPublisher: VideoPacketPublisher?
    private let videoCallbackQueue = DispatchQueue(label: "AeroSpatial.DJI.EncodedVideo", qos: .userInitiated)
    private var videoReceiver: DJIEncodedVideoReceiver?
    private var onDeviceEvidence: ((DeviceEvidence?) -> Void)?

    func observeCapabilities(_ observer: @escaping (DeviceEvidence?) -> Void) {
        onDeviceEvidence = observer
    }

    func attachVideoPublisher(_ publisher: VideoPacketPublisher?) {
        videoPublisher = publisher
    }

    private func startVideoFeed() {
        guard let publisher = videoPublisher, videoReceiver == nil else { return }
        publisher.markDiscontinuity()
        let receiver = DJIEncodedVideoReceiver(publisher: publisher)
        videoReceiver = receiver
        DJISDKManager.videoFeeder().primaryVideoFeed.add(receiver, with: videoCallbackQueue)
    }

    private func stopVideoFeed() {
        guard let receiver = videoReceiver else { return }
        receiver.deactivate()
        DJISDKManager.videoFeeder().primaryVideoFeed.removeListener(receiver)
        videoReceiver = nil
    }

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
        stopVideoFeed()
        onDeviceEvidence?(nil)
        pollTimer?.invalidate()
        pollTimer = nil
        snapshot.connected = false
        snapshot.flying = false
        snapshot.position = nil
        snapshot.altitudeMeters = nil
        snapshot.headingDegrees = nil
        snapshot.gimbalPitchDegrees = nil
        snapshot.batteryPercent = nil
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
        guard connected != snapshot.connected else { return }
        if !connected {
            // A missed SDK disconnect callback must not leave the old video feed
            // or device capability evidence alive.
            disconnect()
            onStatus?("Device link lost during telemetry polling. Camera and controls stopped.")
        } else {
            // A new SDK productConnected event must establish the exact model
            // and the delegates. Polling alone cannot authorize a device.
            onStatus?("DJI link returned; waiting for validated product callback.")
        }
        // Never mark stale telemetry as fresh merely because a connection was polled.
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
            self.stopVideoFeed()
            let model = aircraft.model
            guard AircraftProfile.identify(model).isInitialBenchTarget else {
                self.snapshot.connected = false
                self.onDeviceEvidence?(nil)
                self.onSnapshot?(self.snapshot)
                self.onStatus?("Aircraft model is not the validated Mavic Air 2 adapter target. Telemetry and commands disabled until an explicit driver is added.")
                return
            }
            self.snapshot.connected = true
            // Component presence is observable from the SDK but not a verified
            // hardware capability. Deliberately keep the verified bit false.
            let axes: Set<GimbalAxis> = aircraft.gimbal == nil ? [] : [.pitch]
            if let evidence = DeviceEvidence(identifier: model ?? "Mavic Air 2",
                                             firmware: "unverified",
                                             observedAt: ProcessInfo.processInfo.systemUptime,
                                             axes: axes,
                                             telemetry: aircraft.flightController != nil,
                                             video: aircraft.camera != nil,
                                             verified: false) {
                self.onDeviceEvidence?(evidence)
            }
            self.onSnapshot?(self.snapshot)
            self.onStatus?("Mavic Air 2 detected. SDK, firmware and gimbal remain unverified until physical bench acceptance.")
            aircraft.flightController?.delegate = self
            aircraft.gimbal?.delegate = self
            aircraft.battery?.delegate = self
            self.startVideoFeed()
            self.pollTimer?.invalidate()
            self.pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
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
        let location = state.aircraftLocation
        let coordinate = location?.coordinate
        let locationSample = coordinate.map { GeoPoint(latitude: $0.latitude, longitude: $0.longitude) }
        let altitude = state.altitude
        let heading = Double(state.attitude.yaw)
        let flying = state.isFlying
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.snapshot.uptime = ProcessInfo.processInfo.systemUptime
            self.snapshot.position = locationSample?.isValid == true ? locationSample : nil
            self.snapshot.altitudeMeters = altitude.isFinite ? Double(altitude) : nil
            self.snapshot.headingDegrees = heading.isFinite ? Angle.compassDegrees(heading) : nil
            self.snapshot.flying = flying
            self.onSnapshot?(self.snapshot)
        }
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
