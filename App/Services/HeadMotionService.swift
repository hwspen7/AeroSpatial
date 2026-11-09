import Foundation
import CoreMotion
import AeroSpatialCore

@MainActor
final class HeadMotionService {
    var onSample: ((HeadSample) -> Void)?
    var onStatus: ((String) -> Void)?
    var onActiveChange: ((Bool) -> Void)?
    private let manager = CMHeadphoneMotionManager()
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "AeroSpatial.HeadMotion"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    func start() {
        guard manager.isDeviceMotionAvailable else {
            onActiveChange?(false)
            onStatus?("No compatible headphone motion source. Pair supported AirPods and try again.")
            return
        }
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
            Task { @MainActor [weak self] in self?.onSample?(sample) }
        }
        onActiveChange?(true)
        onStatus?("Headphone motion stream started. Calibrate before enabling gimbal control.")
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        onActiveChange?(false)
        onStatus?("Headphone motion stopped.")
    }
}
