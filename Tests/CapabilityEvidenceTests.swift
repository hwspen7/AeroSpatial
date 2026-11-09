import XCTest
@testable import AeroSpatialCore

final class CapabilityEvidenceTests: XCTestCase {
    func testPhysicalHardwarePresenceDoesNotAuthorizeActuation() {
        let evidence = CapabilityEvidence(productModel: "Mavic Air 2", connected: true,
            flightControllerPresent: true, cameraPresent: true,
            gimbalPresent: true, source: .dji)
        XCTAssertEqual(evidence.observedCapabilities.deviceIdentifier, "Mavic Air 2")
        XCTAssertTrue(evidence.observedCapabilities.canReadVideo)
        XCTAssertTrue(evidence.observedCapabilities.canReadTelemetry)
        XCTAssertFalse(evidence.observedCapabilities.allowsPitchCommand(connected: true,
                                                                       hardwareVerified: false))
    }

    func testDisconnectedHardwareCannotClaimReadiness() {
        let evidence = CapabilityEvidence(productModel: "unknown", connected: false,
            flightControllerPresent: true, cameraPresent: true,
            gimbalPresent: true, source: .dji)
        XCTAssertFalse(evidence.observedCapabilities.canReadTelemetry)
        XCTAssertFalse(evidence.observedCapabilities.canReadVideo)
    }
}
