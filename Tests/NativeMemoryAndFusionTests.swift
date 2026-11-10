import Foundation
import XCTest
@testable import AeroSpatialCore

final class NativeMemoryAndFusionTests: XCTestCase {
    func testImmutableNativeLeaseBudgetAndRetain() throws {
        let pool = try XCTUnwrap(NativeMemoryPool(maximumBytes: 8, maximumPayloadBytes: 8))
        let lease = try XCTUnwrap(pool.copy(Data([1, 2, 3, 4])))
        let copy = try XCTUnwrap(lease.retained())
        XCTAssertEqual(copy.withUnsafeBytes { Array($0) }, [1, 2, 3, 4])
        XCTAssertEqual(pool.statistics?.live_bytes, 4)
        XCTAssertNil(pool.copy(Data(repeating: 1, count: 6)))
        XCTAssertEqual(lease.count, 4)
    }

    func testQueueLeaseRetainsPayloadAfterDequeue() throws {
        let queue = try XCTUnwrap(NativeWorkQueue(maximumEvents: 2,
                         maximumBytes: 32, maximumPayloadBytes: 16))
        let payload = Data([9, 8, 7, 6])
        let work = NativeWorkQueue.Work(traceID: 1, receivedNanoseconds: 10,
                            deadlineNanoseconds: 100, kind: 0,
                            priority: .optional, payload: payload)
        XCTAssertEqual(queue.push(work, at: 10), .accepted)
        let lease = try XCTUnwrap(queue.popLeased(at: 20))
        XCTAssertEqual(lease.traceID, 1)
        XCTAssertEqual(lease.withUnsafeBytes { Array($0) }, [9, 8, 7, 6])
        XCTAssertEqual(queue.report()?.queue_bytes, 0)
        queue.close()
        XCTAssertEqual(lease.withUnsafeBytes { Array($0) }, [9, 8, 7, 6])
    }

    func testLatePositionReplayIsBoundedAndValidated() throws {
        let pose = SpatialPose3(position: SpatialVector(east: 0, north: 0, up: 0),
                                orientation: SpatialQuaternion(w: 1, x: 0, y: 0, z: 0))
        let fusion = try XCTUnwrap(OnlineFusion(timeSeconds: 1, initialPose: pose,
            initialStandardDeviations: [1, 1, 0.1, 0.1, 0.1],
            noise: InertialNoise(accelerometerStd: 0.1, gyroscopeStd: 0.01,
                accelerometerBiasWalk: 0.001, gyroscopeBiasWalk: 0.001,
                maximumStepSeconds: 0.1)))
        for i in 1...4 {
            XCTAssertEqual(fusion.predict(sequence: UInt64(i),
                at: 1 + Double(i) * 0.01,
                specificForce: SpatialVector(east: 0, north: 0, up: 9.80665),
                angularVelocity: SpatialVector(east: 0, north: 0, up: 0)), .accepted)
        }
        XCTAssertEqual(fusion.observeDelayedPosition(sequence: 1, at: 1.02,
            position: SpatialVector(east: 0.2, north: 0, up: 0),
            standardDeviationMeters: 0.5), .accepted)
        XCTAssertEqual(fusion.observeDelayedPosition(sequence: 2, at: 1.025,
            position: SpatialVector(east: 0, north: 0, up: 0),
            standardDeviationMeters: 0.5), .rejected)
        XCTAssertEqual(fusion.observeDelayedPosition(sequence: 2, at: 1.03,
            position: SpatialVector(east: 10000, north: 0, up: 0),
            standardDeviationMeters: 0.5), .rejectedOutlier)
        XCTAssertEqual(fusion.snapshot()?.report.corrected, 1)
    }

    func testOnlineFusionRejectsBadTimeAndOutlier() throws {
        let pose = SpatialPose3(position: SpatialVector(east: 0, north: 0, up: 0),
                                orientation: SpatialQuaternion(w: 1, x: 0, y: 0, z: 0))
        let estimator = try XCTUnwrap(OnlineFusion(timeSeconds: 1, initialPose: pose,
                     initialStandardDeviations: [1, 1, 0.1, 0.1, 0.1],
                     noise: InertialNoise(accelerometerStd: 0.1, gyroscopeStd: 0.01,
                           accelerometerBiasWalk: 0.001, gyroscopeBiasWalk: 0.001,
                           maximumStepSeconds: 0.1)))
        XCTAssertEqual(estimator.predict(sequence: 1, at: 1.01,
                        specificForce: SpatialVector(east: 0, north: 0, up: 9.80665),
                        angularVelocity: SpatialVector(east: 0, north: 0, up: 0)), .accepted)
        XCTAssertEqual(estimator.observePosition(sequence: 1, at: 1.01,
                        position: SpatialVector(east: 0.1, north: 0, up: 0),
                        standardDeviationMeters: 1), .accepted)
        XCTAssertEqual(estimator.observePosition(sequence: 2, at: 1.01,
                        position: SpatialVector(east: 1000, north: 0, up: 0),
                        standardDeviationMeters: 1), .rejectedOutlier)
        XCTAssertEqual(estimator.snapshot()?.covariance.count, 225)
        XCTAssertEqual(estimator.predict(sequence: 2, at: 2,
                        specificForce: SpatialVector(east: 0, north: 0, up: 9.80665),
                        angularVelocity: SpatialVector(east: 0, north: 0, up: 0)), .resetRequired)
    }
}
