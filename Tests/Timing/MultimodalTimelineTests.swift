import XCTest
@testable import AeroSpatialCore

final class MultimodalTimelineTests: XCTestCase {
    private func point(_ stream: SpatialStream, _ sequence: UInt64,
                       _ normalized: UInt64, clock: UInt32 = 1,
                       uncertainty: UInt64 = 1, quality: SpatialQuality = [.valid]) -> TimelinePoint {
        let event = SpatialEvent(stream: stream, timestampNanoseconds: normalized,
                                 sequence: sequence, clockDomain: clock, traceID: 11,
                                 kind: 0, quality: quality, missed: 0, payload: Data([1]))
        return TimelinePoint(event: event, alignedNanoseconds: normalized,
                             uncertaintyNanoseconds: uncertainty)!
    }

    func testCrossClockRequiresExplicitNormalization() {
        var timeline = MultimodalTimeline(capacityPerStream: 4)
        XCTAssertTrue(timeline.append(point(.head, 1, 10_000, clock: 1)))
        XCTAssertTrue(timeline.append(point(.telemetry, 1, 10_004, clock: 7)))
        let result = timeline.aligned(at: 10_002, requiring: [.head, .telemetry],
                                      maximumSkewNanoseconds: 8,
                                      maximumClockUncertaintyNanoseconds: 2)
        XCTAssertEqual(result?.maximumObservedSkewNanoseconds, 2)
        XCTAssertEqual(result?.observations[.telemetry]?.sourceClockDomain, 7)
        XCTAssertNil(timeline.aligned(at: 10_002, requiring: [.head, .video],
                                      maximumSkewNanoseconds: 8,
                                      maximumClockUncertaintyNanoseconds: 2))
    }

    func testBoundsIncludeClockUncertainty() {
        var timeline = MultimodalTimeline()
        timeline.append(point(.head, 1, 1_005, uncertainty: 3))
        XCTAssertNil(timeline.aligned(at: 1_000, requiring: [.head],
                                      maximumSkewNanoseconds: 7,
                                      maximumClockUncertaintyNanoseconds: 5))
        XCTAssertNotNil(timeline.aligned(at: 1_000, requiring: [.head],
                                         maximumSkewNanoseconds: 8,
                                         maximumClockUncertaintyNanoseconds: 5))
        XCTAssertNil(timeline.aligned(at: 1_000, requiring: [.head],
                                      maximumSkewNanoseconds: 8,
                                      maximumClockUncertaintyNanoseconds: 2))
    }

    func testRejectsStaleOutOfOrderAndDuplicate() {
        var timeline = MultimodalTimeline(capacityPerStream: 2)
        XCTAssertTrue(timeline.append(point(.head, 1, 100)))
        XCTAssertFalse(timeline.append(point(.head, 1, 101)))
        XCTAssertFalse(timeline.append(point(.head, 2, 99)))
        XCTAssertEqual(timeline.rejected, 2)
        XCTAssertTrue(timeline.append(point(.head, 2, 101, quality: [.valid, .stale])))
        XCTAssertNil(timeline.aligned(at: 101, requiring: [.head],
                                      maximumSkewNanoseconds: 2,
                                      maximumClockUncertaintyNanoseconds: 2))
    }

    func testWrapAndLargeUnsignedTimestamps() {
        var timeline = MultimodalTimeline(capacityPerStream: 2)
        let baseline = UInt64.max - 100
        for index in 0..<4 {
            timeline.append(point(.head, UInt64(index + 1), baseline + UInt64(index * 10)))
        }
        let result = timeline.aligned(at: baseline + 29, requiring: [.head],
                                      maximumSkewNanoseconds: 4,
                                      maximumClockUncertaintyNanoseconds: 2)
        XCTAssertEqual(result?.observations[.head]?.sequence, 4)
        XCTAssertNil(timeline.aligned(at: baseline, requiring: [.head],
                                      maximumSkewNanoseconds: 4,
                                      maximumClockUncertaintyNanoseconds: 2))
    }
}
