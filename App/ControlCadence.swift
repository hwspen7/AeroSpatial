import Foundation
import AeroSpatialCore

/// Monotonic scheduling separate from SwiftUI's run loop. The user-facing
/// control state remains @MainActor and is never delegated to a video worker.
/// This is NOT a hard-real-time scheduler or a substitute for device failsafes.
final class ControlCadence: @unchecked Sendable {
    private let queue = DispatchQueue(label: "AeroSpatial.ControlCadence", qos: .userInitiated)
    private let mutex = NSLock()
    private var timer: DispatchSourceTimer?
    private var inFlight = false
    private var stopped = false
    private var missed: UInt64 = 0
    private let jitter = NativeRuntimeMetrics(deadlineNanoseconds: 20_000_000)

    func start(interval: TimeInterval = 0.15, tick: @escaping @Sendable (UInt64) -> Void) {
        guard interval >= 0.02, interval <= 1 else { return }
        mutex.lock()
        guard timer == nil, !stopped else { mutex.unlock(); return }
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(5))
        source.setEventHandler { [weak self] in
            guard let self else { return }
            self.mutex.lock()
            guard !self.stopped else { self.mutex.unlock(); return }
            if self.inFlight {
                self.missed &+= 1
                self.mutex.unlock()
                return
            }
            self.inFlight = true
            self.mutex.unlock()
            tick(DispatchTime.now().uptimeNanoseconds)
        }
        timer = source
        mutex.unlock()
        source.resume()
    }

    /// Called after the actor-delivered tick finishes; time includes any actor wait.
    func completed(scheduledAt started: UInt64) {
        let now = DispatchTime.now().uptimeNanoseconds
        if now >= started { _ = jitter?.record(now - started) }
        mutex.lock()
        inFlight = false
        mutex.unlock()
    }

    func stop() {
        mutex.lock()
        stopped = true
        let source = timer
        timer = nil
        mutex.unlock()
        source?.cancel()
    }

    struct Diagnostic {
        let missed: UInt64
        let samples: UInt64
        let p95UpperNanoseconds: UInt64
    }

    func diagnostic() -> Diagnostic {
        mutex.lock()
        let count = missed
        mutex.unlock()
        let report = jitter?.report()
        return Diagnostic(missed: count, samples: report?.samples ?? 0,
                          p95UpperNanoseconds: report?.p95_upper_ns ?? 0)
    }
    deinit { stop() }
}
