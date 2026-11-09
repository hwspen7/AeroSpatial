import XCTest
@testable import AeroSpatialCore

final class NativeEstimationTests: XCTestCase {
    func testSE3RoundtripAndInverse() throws {
        let twist: [Double] = [1, -2, 3, 0.03, -0.04, 0.05]
        let pose = try XCTUnwrap(NativePoseMath.exponential(twist))
        let recovered = try XCTUnwrap(NativePoseMath.logarithm(pose))
        for (a, b) in zip(twist, recovered) { XCTAssertEqual(a, b, accuracy: 1e-8) }
        let inverse = try XCTUnwrap(NativePoseMath.inverse(pose))
        let identity = try XCTUnwrap(NativePoseMath.composed(pose, with: inverse))
        XCTAssertEqual(identity.position.east, 0, accuracy: 1e-8)
        XCTAssertEqual(identity.position.north, 0, accuracy: 1e-8)
        XCTAssertEqual(identity.position.up, 0, accuracy: 1e-8)
    }

    func testNativeCovarianceAndInvalidInputs() throws {
        let identity = try XCTUnwrap(NativePoseMath.exponential(Array(repeating: 0, count: 6)))
        let diagonal = (0..<36).map { $0 / 6 == $0 % 6 ? 1.0 : 0.0 }
        let cov = try XCTUnwrap(NativePoseMath.composedCovariance(identity,
                                                                   first: diagonal, second: diagonal))
        XCTAssertEqual(cov[0], 2, accuracy: 1e-12)
        XCTAssertEqual(cov[35], 2, accuracy: 1e-12)
        XCTAssertNil(NativePoseMath.exponential([1, 2, 3]))
        XCTAssertNil(NativePoseMath.exponential([1, 2, .nan, 0, 0, 0]))
    }

    func testStationaryInertialPredictionAndOutlier() throws {
        var estimator = InertialEstimator()
        let pose = try XCTUnwrap(NativePoseMath.exponential(Array(repeating: 0, count: 6)))
        XCTAssertTrue(estimator.initialize(at: 0, pose: pose,
                                           initialStandardDeviations: [2, 1, 0.1, 0.1, 0.1]))
        let noise = InertialNoise(accelerometerStd: 0.08, gyroscopeStd: 0.005,
                                  accelerometerBiasWalk: 0.005, gyroscopeBiasWalk: 0.0005)
        for i in 1...100 {
            XCTAssertTrue(estimator.predict(at: Double(i) / 100,
                                             specificForce: .init(east: 0, north: 0, up: 9.80665),
                                             angularVelocityRadians: .init(east: 0, north: 0, up: 0),
                                             noise: noise))
        }
        XCTAssertEqual(try XCTUnwrap(estimator.pose).position.up, 0, accuracy: 1e-7)
        let covariance = try XCTUnwrap(estimator.errorCovariance)
        XCTAssertEqual(covariance.count, 225)
        XCTAssertGreaterThan(covariance[0], 0)
        XCTAssertEqual(covariance[14*15 + 14], covariance[14*15 + 14], accuracy: 1e-12)
        if case .rejectedOutlier = estimator.observePosition(
            .init(east: 1000, north: 0, up: 0), standardDeviationMeters: 1) { } else {
            XCTFail("Large position innovation must be rejected")
        }
        XCTAssertFalse(estimator.predict(at: 20,
                                         specificForce: .init(east: 0, north: 0, up: 9.80665),
                                         angularVelocityRadians: .init(east: 0, north: 0, up: 0), noise: noise))
    }
}
