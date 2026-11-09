#if canImport(DJISDK)
import Foundation
import DJISDK
import AeroSpatialCore
#if canImport(DJIWidget)
import DJIWidget
#endif

/// Receives transport packets, NOT decoded frames. H.264 access-unit assembly,
/// timestamp calibration and hardware decoder output require a separate stage.
final class DJIVideoIngress: NSObject, DJIVideoFeedListener {
    private let bus: SpatialBus
    private let callbackQueue = DispatchQueue(label: "aerospatial.dji.video", qos: .userInitiated)
    private let clockDomain: UInt32 = 90  // Host monotonic receipt time, not capture time.
    private let stateLock = NSLock()
    private var enabled = false

    init(bus: SpatialBus) { self.bus = bus }

    func start() {
        stateLock.lock()
        let shouldStart = !enabled
        enabled = true
        stateLock.unlock()
        if shouldStart { DJISDKManager.videoFeeder()?.primaryVideoFeed.add(self, with: callbackQueue) }
    }

    func stop() {
        stateLock.lock()
        let wasEnabled = enabled
        enabled = false
        stateLock.unlock()
        if wasEnabled { DJISDKManager.videoFeeder()?.primaryVideoFeed.removeListener(self) }
    }

    // DJISDK invokes this on callbackQueue. The native bus provides bounded
    // admission, so no unbounded DispatchQueue or array is created here.
    func videoFeed(_ videoFeed: DJIVideoFeed, didUpdateVideoData videoData: Data) {
        stateLock.lock()
        let accepting = enabled
        stateLock.unlock()
        guard accepting, !videoData.isEmpty, videoData.count <= 2 * 1024 * 1024 else { return }
        let received = ProcessInfo.processInfo.systemUptime
        guard received.isFinite, received >= 0 else { return }
        _ = bus.publish(stream: .video, timestampNanoseconds: UInt64(received * 1_000_000_000),
                        clockDomain: clockDomain, kind: 0x1001,
                        quality: [.valid, .clockEstimated], payload: videoData)
        #if canImport(DJIWidget)
        // DJIWidget decodes the H.264 transport stream for live UI preview.
        // This is not a CVPixelBuffer inference callback and is not a capture timestamp.
        var packet = videoData
        let count = Int32(packet.count)
        packet.withUnsafeMutableBytes { raw in
            if let bytes = raw.bindMemory(to: UInt8.self).baseAddress {
                DJIVideoPreviewer.instance().push(bytes, length: count)
            }
        }
        #endif
    }
}
#endif
