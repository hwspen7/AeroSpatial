import XCTest
@testable import AeroSpatialCore

final class FrameBundleTests: XCTestCase {
    private func point(_ stream: SpatialStream, _ time: UInt64,
                       clock: UInt32) -> TimelinePoint {
        let event = SpatialEvent(stream: stream, timestampNanoseconds: time,
                                 sequence: 1, clockDomain: clock, traceID: 10,
                                 kind: 0, quality: [.valid], missed: 0, payload: Data())
        return TimelinePoint(event: event, alignedNanoseconds: time,
                             uncertaintyNanoseconds: 2)!
    }

    func testRequiresAllThreeStreamsWithExplicitClockAlignment() {
        var timeline = MultimodalTimeline()
        timeline.append(point(.head, 100, clock: 1))
        timeline.append(point(.telemetry, 101, clock: 2))
        XCTAssertNil(FrameBundle.resolve(in: timeline, at: 100, maximumSkewNanoseconds: 5,
                                         maximumClockUncertaintyNanoseconds: 2))
        timeline.append(point(.video, 102, clock: 3))
        let bundle = FrameBundle.resolve(in: timeline, at: 100, maximumSkewNanoseconds: 5,
                                         maximumClockUncertaintyNanoseconds: 2)
        XCTAssertEqual(bundle?.maximumSkewNanoseconds, 2)
        XCTAssertEqual(bundle?.telemetry.sourceClockDomain, 2)
        XCTAssertNil(FrameBundle.resolve(in: timeline, at: 100, maximumSkewNanoseconds: 3,
                                         maximumClockUncertaintyNanoseconds: 2))
    }
}
