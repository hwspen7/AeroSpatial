import Foundation
import CoreMotion
import AeroSpatialCore

@MainActor
final class HeadMotionService {
    var onSample: ((HeadSample) -> Void)?
    var onClockPair: ((Double, Double) -> Void)?
    var onStatus: ((String) -> Void)?
    var onActiveChange: ((Bool) -> Void)?
    private let manager = CMHeadphoneMotionManager()
    private let ingress = RealtimeHeadIngress(capacity: 256)!
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "AeroSpatial.HeadMotion"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    func start() {
        _ = ingress.takeLatest()
        guard manager.isDeviceMotionAvailable else {
            onActiveChange?(false)
            onStatus?("No compatible headphone motion source. Pair supported AirPods and try again.")
            return
        }
        let buffer = ingress
        manager.startDeviceMotionUpdates(to: queue) { [weak self] motion, error in
            if let error = error {
                Task { @MainActor [weak self] in
                    self?.onStatus?("Head motion: \(error.localizedDescription)")
                    self?.onActiveChange?(false)
                }
                return
            }
            guard let motion = motion else { return }
            let degrees = 180.0 / Double.pi
            let sample = HeadSample(uptime: motion.timestamp,
                                    pose: HeadPose(yaw: motion.attitude.yaw * degrees,
                                                   pitch: motion.attitude.pitch * degrees,
                                                   roll: motion.attitude.roll * degrees))
            _ = buffer.offer(sample, receivedAt: ProcessInfo.processInfo.systemUptime)
        }
        onActiveChange?(true)
        onStatus?("Headphone motion stream started. Calibrate before enabling gimbal control.")
    }

    func drainLatest() {
        if let result = ingress.takeLatestObservation() {
            onClockPair?(result.sample.uptime, result.receivedHostSeconds)
            onSample?(result.sample)
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        _ = ingress.takeLatest()
        onActiveChange?(false)
        onStatus?("Headphone motion stopped.")
    }
}
