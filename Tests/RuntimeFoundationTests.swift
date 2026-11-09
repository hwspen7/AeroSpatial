import Foundation
import XCTest
@testable import AeroSpatialCore

final class RuntimeFoundationTests: XCTestCase {
    private func event(_ stream: SpatialStream, _ sequence: UInt64, _ clock: UInt32 = 1)
        -> SpatialEvent {
        SpatialEvent(stream: stream, timestampNanoseconds: sequence * 10_000_000,
                     sequence: sequence, clockDomain: clock, traceID: 0, kind: 0,
                     quality: [.valid], missed: 0, payload: Data([UInt8(sequence % 256)]))
    }

    func testRealtimeIngressPrioritiesAndBounds() async {
        let ingress = RealtimeIngress(essentialLimit: 2, optionalLimit: 2)
        let first = await ingress.offer(event(.head, 1), lane: .essential)
        XCTAssertEqual(first, .accepted)
        let second = await ingress.offer(event(.telemetry, 2), lane: .essential)
        XCTAssertEqual(second, .accepted)
        let third = await ingress.offer(event(.head, 3), lane: .essential)
        XCTAssertEqual(third, .rejected)
        _ = await ingress.offer(event(.video, 1), lane: .optional)
        _ = await ingress.offer(event(.video, 2), lane: .optional)
        let replaced = await ingress.offer(event(.video, 3), lane: .optional)
        XCTAssertEqual(replaced, .overwritten)
        let result = await ingress.take(maximum: 8)
        XCTAssertEqual(result.map(\.sequence), [1, 2, 2, 3])
        let stats = await ingress.snapshot()
        XCTAssertEqual(stats.counters.overwritten, 1)
        XCTAssertEqual(stats.counters.rejected, 1)
        XCTAssertEqual(stats.counters.drained, 4)
    }

    func testClockRegistryRobustnessAndReset() async {
        let registry = OnlineClockRegistry()
        for i in 1...16 {
            let status = await registry.observe(domain: 7, sourceSeconds: Double(i),
                                                hostSeconds: Double(i) + 0.25)
            XCTAssertEqual(status, .accepted)
        }
        let outlier = await registry.observe(domain: 7, sourceSeconds: 17, hostSeconds: 20)
        XCTAssertEqual(outlier, .outlier)
        let aligned = await registry.translate(domain: 7, sourceSeconds: 16)
        XCTAssertNotNil(aligned)
        XCTAssertEqual(aligned!.alignedNanoseconds, 16_250_000_000)
        let missing = await registry.translate(domain: 8, sourceSeconds: 3)
        XCTAssertNil(missing)
        await registry.reset(domain: 7)
        let resetValue = await registry.translate(domain: 7, sourceSeconds: 16)
        XCTAssertNil(resetValue)
    }

    func testDeviceEvidenceFailClosed() async {
        let discovery = DeviceDiscovery()
        let initial = await discovery.resolve(now: 1)
        XCTAssertEqual(initial, .unverifiedDJI)
        let unverified = DeviceEvidence(identifier: "air2", firmware: "unknown", observedAt: 1,
                                        axes: [.pitch], telemetry: true, video: true, verified: false)!
        await discovery.record(unverified)
        let notTrusted = await discovery.resolve(now: 1.1)
        XCTAssertFalse(notTrusted.canReadTelemetry)
        let verified = DeviceEvidence(identifier: "air2", firmware: "measured", observedAt: 2,
                                      axes: [.pitch], telemetry: true, video: false, verified: true)!
        await discovery.record(verified)
        let live = await discovery.resolve(now: 2.1)
        XCTAssertTrue(live.canReadTelemetry)
        XCTAssertFalse(live.canReadVideo)
        let expired = await discovery.resolve(now: 5)
        XCTAssertEqual(expired, .unverifiedDJI)
    }

    func testSupervisorAllHazards() {
        let monitor = SafetySupervisor()
        func check(_ now: Double, _ authorized: Bool, _ connected: Bool, _ flying: Bool,
                   _ h: Double?, _ t: Double?, _ verified: Bool) -> SafetySupervisor.Decision {
            monitor.assess(now: now, authorized: authorized, connected: connected,
                           flying: flying, lastHead: h, lastTelemetry: t,
                           pitchCapabilityVerified: verified)
        }
        XCTAssertEqual(check(2, true, true, false, 1.9, 1.9, true).permitted, true)
        XCTAssertEqual(check(2, false, true, false, 1.9, 1.9, true).reason, .operatorNotAuthorized)
        XCTAssertEqual(check(2, true, false, false, 1.9, 1.9, true).reason, .disconnected)
        XCTAssertEqual(check(2, true, true, true, 1.9, 1.9, true).reason, .aircraftInFlight)
        XCTAssertEqual(check(2, true, true, false, 1.9, 1.9, false).reason, .capabilityMissing)
        XCTAssertEqual(check(2, true, true, false, 0, 1.9, true).reason, .staleHead)
        XCTAssertEqual(check(2, true, true, false, 1.9, 0, true).reason, .staleTelemetry)
        XCTAssertEqual(check(.nan, true, true, false, 1.9, 1.9, true).reason, .invalidClock)
    }

    func testRollingPerformancePercentiles() {
        var monitor = PerformanceBudget(capacity: 4, maximumAllowedNanoseconds: 100)
        XCTAssertFalse(monitor.isHealthy)
        for value in [10, 20, 30, 200, 40] as [UInt64] { monitor.observe(value) }
        let report = monitor.report()!
        XCTAssertEqual(report.samples, 4)
        XCTAssertEqual(report.p95Nanoseconds, 200)
        XCTAssertEqual(report.exceedingLimit, 1)
        XCTAssertFalse(monitor.isHealthy)
    }

    func testVideoAlignmentRequiresThreeStreams() async {
        let pipeline = VideoSensorPipeline()
        let videoOK = await pipeline.observe(event(.video, 1), alignedNanoseconds: 1_000_000_000,
                                             uncertaintyNanoseconds: 1_000_000)
        XCTAssertTrue(videoOK)
        let incomplete = await pipeline.bundle(at: 1_000_000_000)
        XCTAssertNil(incomplete)
        let headOK = await pipeline.observe(event(.head, 1), alignedNanoseconds: 1_001_000_000,
                                            uncertaintyNanoseconds: 1_000_000)
        XCTAssertTrue(headOK)
        let telemetryOK = await pipeline.observe(event(.telemetry, 1), alignedNanoseconds: 999_000_000,
                                                 uncertaintyNanoseconds: 1_000_000)
        XCTAssertTrue(telemetryOK)
        let joined = await pipeline.bundle(at: 1_000_000_000)
        XCTAssertNotNil(joined)
        let strict = await pipeline.bundle(at: 1_000_000_000,
                                           maximumUncertaintyNanoseconds: 10)
        XCTAssertNil(strict)
    }

    func testDurableAsyncJournalAndRecovery() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let writer = try AsyncJournalWriter(directory: dir, segmentBytes: 1024, maximumSegments: 2)
        try await writer.append(Data(repeating: 0xAA, count: 200))
        try await writer.append(Data(repeating: 0xBB, count: 200))
        let written = await writer.written
        XCTAssertEqual(written, 2)
        let recovered = try SegmentJournal(directory: dir, segmentBytes: 1024, maximumSegments: 2)
        try await recovered.append(Data(repeating: 0xCC, count: 200))
    }

}

extension RuntimeFoundationTests {
    func testVideoIngressConnectedToNativeBus() async throws {
        let bus = try SpatialBus(payloadBudgetBytes: 4 * 1024 * 1024)
        let receiver = try XCTUnwrap(bus.subscribe(.video, latest: false))
        let pipeline = DeviceVideoPipeline(bus: bus)
        let frame = try XCTUnwrap(EncodedFrame(bytes: Data([0, 0, 0, 1, 0x65]), codec: .h264,
                                              timestampNanoseconds: 1, clockDomain: 8,
                                              traceID: 55, estimatedClock: true))
        let accepted = await pipeline.accept(frame)
        XCTAssertTrue(accepted)
        let message = try XCTUnwrap(receiver.next())
        XCTAssertEqual(message.traceID, 55)
        XCTAssertEqual(message.payload, frame.bytes)
        XCTAssertTrue(message.quality.contains(.clockEstimated))
        let again = await pipeline.accept(frame)
        XCTAssertTrue(again)
        let count = await pipeline.forwarded
        XCTAssertEqual(count, 2)
    }
}

extension RuntimeFoundationTests {
    func testNativeHistogram() {
        let counter = NativeRuntimeMetrics(deadlineNanoseconds: 100)!
        for value in [10, 20, 30, 200] as [UInt64] { XCTAssertTrue(counter.record(value)) }
        let result = counter.report()!
        XCTAssertEqual(result.samples, 4)
        XCTAssertEqual(result.breaches, 1)
        XCTAssertEqual(result.maximum_ns, 200)
        XCTAssertGreaterThanOrEqual(result.p99_upper_ns, 200)
    }
}

extension RuntimeFoundationTests {
    func testOffMainIngressPublisher() async throws {
        let bus = try SpatialBus()
        let subscriber = try XCTUnwrap(bus.subscribe(.head, latest: false))
        let publisher = SpatialIngressPublisher(bus: bus, capacity: 16)
        XCTAssertTrue(publisher.send(head: HeadSample(uptime: 5,
                          pose: HeadPose(yaw: 1, pitch: 2, roll: 3))))
        var received: SpatialEvent?
        for _ in 0..<100 {
            received = try subscriber.next()
            if received != nil { break }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        XCTAssertEqual(received?.stream, .head)
        let pose = try JSONDecoder().decode(HeadSample.self, from: XCTUnwrap(received?.payload))
        XCTAssertEqual(pose.pose.yaw, 1)
    }
}
