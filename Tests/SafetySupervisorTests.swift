import XCTest
@testable import AeroSpatialCore

final class SafetySupervisorTests: XCTestCase {
    func testPermissionAndEveryInterlock() {
        let guardrail = SafetySupervisor()
        func check(auth: Bool = true, fg: Bool = true, connected: Bool = true,
                   flying: Bool = false, head: Bool = true, headAge: Double = 0.04,
                   telAge: Double = 0.2, verified: Bool = true, pending: Bool = false) -> SafetyDecision {
            guardrail.evaluate(SafetyContext(authorized: auth, appForeground: fg,
                aircraftConnected: connected, aircraftFlying: flying, headAvailable: head,
                headAgeSeconds: headAge, telemetryAgeSeconds: telAge,
                hardwarePermitted: verified, commandPending: pending))
        }
        XCTAssertEqual(check(), .permitted)
        XCTAssertEqual(check(auth: false), .notAuthorized)
        XCTAssertEqual(check(fg: false), .appInactive)
        XCTAssertEqual(check(connected: false), .connectionLost)
        XCTAssertEqual(check(flying: true), .aircraftFlying)
        XCTAssertEqual(check(head: false), .headUnavailable)
        XCTAssertEqual(check(headAge: .nan), .headStale)
        XCTAssertEqual(check(headAge: 1), .headStale)
        XCTAssertEqual(check(telAge: 3), .telemetryStale)
        XCTAssertEqual(check(verified: false), .unverifiedHardware)
        XCTAssertEqual(check(pending: true), .pendingCommand)
    }
}
