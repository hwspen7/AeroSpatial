import Foundation
import Combine
import AeroSpatialCore

@MainActor
final class AppModel: ObservableObject {
    @Published var mode: DroneMode = .simulation
    @Published var aircraft = AircraftSnapshot(
        uptime: ProcessInfo.processInfo.systemUptime,
        source: .simulator, connected: false, flying: false)
    @Published var head: HeadSample?
    @Published var headSource = "None"
    @Published var headMotionActive = false
    @Published var calibrated = false
    @Published var armed = false
    @Published var recording = false
    @Published var latestSession: URL?
    @Published var location: GeoPoint?
    @Published var phoneHeading: Double?
    @Published var relativePosition: RelativePosition?
    @Published var headRelativeCue: HeadRelativeCue?
    @Published var latestAdvisory: FlightAdvisory?
    @Published var headStreamQuality: StreamStatistics?
    @Published var aircraftStreamQuality: StreamStatistics?
    @Published var spatialCalibrated = false
    @Published var capabilities = DeviceCapabilities.simulator
    var liveBenchEnabled: Bool { BenchSafety.allowsExperimentalGimbal }
    @Published var message = "Ready for simulation."
    @Published var lastDecision = TrackingStatus.disarmed
    @Published var synchronized = false
    @Published var audioEnabled = false {
        didSet { audio.enabled = audioEnabled; if !audioEnabled { audio.silence() } }
    }
    @Published var invertedPitch = false {
        didSet { tracking.settings.invertPitch = invertedPitch }
    }
    @Published var gain = 0.85 {
        didSet { tracking.settings.pitchGain = gain }
    }
    @Published var demoHeadPitch = 0.0 {
        didSet { updateDemoHead() }
    }
    @Published var demoHeadYaw = 0.0 {
        didSet { updateDemoHead() }
    }

    let motion = HeadMotionService()
    let pilot = PilotLocationService()
    let audio = AudioCueService()
    let recorder = SessionRecorder()
    let spatialBus = try? SpatialBus()
    lazy var ingressPublisher = spatialBus.map { SpatialIngressPublisher(bus: $0) }
    var tracking = HeadTrackingController()
    let runtimeSupervisor = SafetySupervisor()
    let controlLatency = NativeRuntimeMetrics(deadlineNanoseconds: 5_000_000)
    var commandGate = GimbalCommandGate()
    var sensorHealth = SensorHealthMonitor()
    var synchronizer = SensorSynchronizer()
    var spatialAwareness = HeadRelativeAwareness()
    var advisor = PassiveAdvisor()
    var adapter: DroneAdapter = SimulatorDroneAdapter()
    var controlTimer: Timer?
    var demoInputEnabled = false
    var started = false

    init() {
        motion.onSample = { [weak self] sample in
            guard let self = self else { return }
            self.demoInputEnabled = false
            guard self.sensorHealth.observeHead(sample, receivedAt: ProcessInfo.processInfo.systemUptime) == .accepted,
                  self.synchronizer.append(sample) else { return }
            self.head = sample
            _ = self.ingressPublisher?.send(head: sample)
            self.headSource = "AirPods motion"
            self.log("head", source: "airpods",
                     fields: ["yaw": sample.pose.yaw, "pitch": sample.pose.pitch, "roll": sample.pose.roll,
                              "sensor_uptime": sample.uptime])
        }
        motion.onActiveChange = { [weak self] active in
            self?.headMotionActive = active
            if !active { self?.disarm() }
        }
        motion.onStatus = { [weak self] status in self?.show(status) }
        pilot.onUpdate = { [weak self] position, heading in
            guard let self = self else { return }
            self.location = position
            self.phoneHeading = heading
            (self.adapter as? SimulatorDroneAdapter)?.updatePilotPosition(position)
            self.calculateRelativePosition()
            self.calculateHeadRelativeCue()
        }
        pilot.onStatus = { [weak self] status in self?.show(status) }
        recorder.onWriteFailure = { [weak self] error in
            guard let self, self.recording else { return }
            self.stopRecording()
            self.show("Recording interrupted: \(error.localizedDescription)")
        }
        configureAdapter()
    }

    func start() {
        guard !started else { return }
        started = true
        adapter.connect()
        controlTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.controlTick() }
        }
    }

    func stop() {
        disarm()
        motion.stop()
        spatialAwareness.reset()
        spatialCalibrated = false
        headRelativeCue = nil
        pilot.stop()
        audio.silence()
        controlTimer?.invalidate()
        controlTimer = nil
        adapter.disconnect()
        commandGate.reset()
        sensorHealth.reset()
        headStreamQuality = nil
        aircraftStreamQuality = nil
        if recording { stopRecording() }
        started = false
    }

    func switchMode(_ newMode: DroneMode) {
        guard mode != newMode else { return }
        disarm()
        motion.stop()
        adapter.disconnect()
        tracking.reset()
        calibrated = false
        head = nil
        headSource = "None"
        demoInputEnabled = false
        synchronizer.reset()
        commandGate.reset()
        sensorHealth.reset()
        headStreamQuality = nil
        aircraftStreamQuality = nil
        synchronized = false
        spatialAwareness.reset()
        spatialCalibrated = false
        headRelativeCue = nil
        advisor.reset()
        latestAdvisory = nil
        mode = newMode
        configureAdapter()
        if started { adapter.connect() }
        log("mode", source: "app", note: newMode.rawValue)
    }

    func configureAdapter() {
        adapter = DroneAdapterFactory.make(mode)
        capabilities = mode == .simulation ? .simulator : .unverifiedDJI
        aircraft = adapter.snapshot
        adapter.onSnapshot = { [weak self] snapshot in
            guard let self = self else { return }
            // Link-down events must not be dropped just because the previous
            // telemetry timestamp has not advanced. They are not fresh data.
            if !snapshot.connected {
                self.aircraft = snapshot
                self.disarm()
                for alert in self.advisor.observe(snapshot) {
                    self.latestAdvisory = alert
                    self.log("advisory", source: "advisor", note: alert.code)
                }
                return
            }
            guard self.sensorHealth.observeAircraft(snapshot, receivedAt: ProcessInfo.processInfo.systemUptime) == .accepted,
                  self.synchronizer.append(snapshot) else { return }
            self.aircraft = snapshot
            _ = self.ingressPublisher?.send(telemetry: snapshot)
            self.calculateRelativePosition()
            self.calculateHeadRelativeCue()
            for alert in self.advisor.observe(snapshot) {
                self.latestAdvisory = alert
                self.log("advisory", source: "advisor",
                         fields: ["related_sensor_uptime": alert.uptime], note: alert.code)
                if snapshot.source == .dji {
                    self.audio.announce(alert.message, key: alert.code, interval: 30)
                }
            }
            var fields: [String: Double] = ["sensor_uptime": snapshot.uptime]
            if let pitch = snapshot.gimbalPitchDegrees { fields["gimbal_pitch"] = pitch }
            if let battery = snapshot.batteryPercent { fields["battery_percent"] = Double(battery) }
            if let position = snapshot.position {
                fields["latitude"] = position.latitude
                fields["longitude"] = position.longitude
            }
            self.log("telemetry", source: snapshot.source.rawValue, fields: fields)
        }
        adapter.onStatus = { [weak self] status in self?.show(status) }
        if let simulator = adapter as? SimulatorDroneAdapter {
            simulator.updatePilotPosition(location)
        }
    }

}
