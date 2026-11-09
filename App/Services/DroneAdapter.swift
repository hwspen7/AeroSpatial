import Foundation
import AeroSpatialCore

@MainActor
protocol DroneAdapter: AnyObject {
    var title: String { get }
    var snapshot: AircraftSnapshot { get }
    var onSnapshot: ((AircraftSnapshot) -> Void)? { get set }
    var onStatus: ((String) -> Void)? { get set }

    func connect()
    func disconnect()
    func setGimbalPitch(_ pitch: Double, completion: @escaping (Result<Void, Error>) -> Void)
}

enum DroneMode: String, CaseIterable, Identifiable {
    case simulation = "Simulation"
    case dji = "DJI MSDK V4"
    var id: String { rawValue }
}

enum AdapterError: LocalizedError {
    case disconnected
    case busy
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .disconnected: "Aircraft is not connected."
        case .busy: "Previous gimbal command is still pending."
        case .unavailable(let message): message
        }
    }
}

@MainActor
final class SimulatorDroneAdapter: DroneAdapter {
    let title = "Simulated Mavic Air 2"
    var snapshot: AircraftSnapshot
    var onSnapshot: ((AircraftSnapshot) -> Void)?
    var onStatus: ((String) -> Void)?
    private var timer: Timer?
    private var pilotPosition: GeoPoint?

    init() {
        snapshot = AircraftSnapshot(uptime: ProcessInfo.processInfo.systemUptime,
                                    source: .simulator, connected: false, flying: false,
                                    altitudeMeters: 38, headingDegrees: 45,
                                    gimbalPitchDegrees: -25, batteryPercent: 87)
    }

    func updatePilotPosition(_ point: GeoPoint?) {
        pilotPosition = point
    }

    func connect() {
        timer?.invalidate()
        snapshot.connected = true
        onStatus?("Simulation connected. No aircraft commands are transmitted.")
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        tick()
    }

    private func tick() {
        snapshot.uptime = ProcessInfo.processInfo.systemUptime
        if let pilotPosition = pilotPosition {
            snapshot.position = GeoPoint(latitude: min(90, pilotPosition.latitude + 0.00035),
                                         longitude: min(180, pilotPosition.longitude + 0.00065))
        } else {
            snapshot.position = nil
        }
        onSnapshot?(snapshot)
    }

    func disconnect() {
        timer?.invalidate()
        timer = nil
        snapshot.connected = false
        onSnapshot?(snapshot)
        onStatus?("Simulation stopped.")
    }

    func setGimbalPitch(_ pitch: Double, completion: @escaping (Result<Void, Error>) -> Void) {
        guard snapshot.connected else { completion(.failure(AdapterError.disconnected)); return }
        snapshot.gimbalPitchDegrees = max(-85, min(0, pitch))
        snapshot.uptime = ProcessInfo.processInfo.systemUptime
        onSnapshot?(snapshot)
        completion(.success(()))
    }
}

@MainActor
final class UnavailableDJIAdapter: DroneAdapter {
    let title = "DJI adapter not installed"
    var snapshot = AircraftSnapshot(uptime: 0, source: .dji, connected: false, flying: false)
    var onSnapshot: ((AircraftSnapshot) -> Void)?
    var onStatus: ((String) -> Void)?
    func connect() {
        onStatus?("DJI SDK is not linked. Build the CocoaPods workspace on a Mac with a registered DJI App Key.")
    }
    func disconnect() { snapshot.connected = false; onSnapshot?(snapshot) }
    func setGimbalPitch(_ pitch: Double, completion: @escaping (Result<Void, Error>) -> Void) {
        completion(.failure(AdapterError.unavailable("DJI SDK is not installed.")))
    }
}

@MainActor
enum DroneAdapterFactory {
    static func make(_ mode: DroneMode) -> DroneAdapter {
        switch mode {
        case .simulation: SimulatorDroneAdapter()
        case .dji:
            #if canImport(DJISDK)
            DJIAdapter()
            #else
            UnavailableDJIAdapter()
            #endif
        }
    }
}
