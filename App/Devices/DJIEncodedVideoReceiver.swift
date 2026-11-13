#if canImport(DJISDK)
import DJISDK
import Foundation
import AeroSpatialCore

/// DJI SDK V4's video callback delivers fragments of an encoded elementary stream.
/// The portable bus preserves fragments and their estimated receipt times.
/// No fragment is advertised as a decoded frame or a verified capture timestamp.
final class DJIEncodedVideoReceiver: NSObject, DJIVideoFeedListener {
    private let publisher: VideoPacketPublisher
    private let lock = NSLock()
    private var active = true

    init(publisher: VideoPacketPublisher) {
        self.publisher = publisher
    }

    nonisolated func videoFeed(_ videoFeed: DJIVideoFeed, didUpdateVideoData videoData: Data) {
        lock.lock()
        defer { lock.unlock() }
        guard active else { return }
        _ = publisher.receive(videoData,
                              receivedAtNanoseconds: DispatchTime.now().uptimeNanoseconds)
    }

    func deactivate() {
        lock.lock()
        active = false
        lock.unlock()
        publisher.markDiscontinuity()
    }
}
#endif
