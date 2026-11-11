import XCTest
@testable import AeroSpatialCore

final class AircraftProfileTests: XCTestCase {
    func testMavicAir2IsTheExplicitInitialAdapterTarget() {
        XCTAssertEqual(AircraftProfile.identify("Mavic Air 2"), .mavicAir2)
        XCTAssertEqual(AircraftProfile.identify(" DJI Mavic Air 2 "), .mavicAir2)
        XCTAssertTrue(AircraftProfile.mavicAir2.isInitialBenchTarget)
        XCTAssertEqual(AircraftProfile.identify("DJI Air 2S"), .air2S)
        XCTAssertFalse(AircraftProfile.air2S.isInitialBenchTarget)
    }

    func testUnknownAndSubstringModelsCannotAccidentallyPass() {
        for model in [nil, "", "Mavic Air", "Mavic Air 20", "Mini 2", "Mavic 2", "Mavic Air 2 Pro"] {
            XCTAssertEqual(AircraftProfile.identify(model), .unrecognized)
            XCTAssertFalse(AircraftProfile.identify(model).isInitialBenchTarget)
        }
    }
}
