import XCTest
@testable import AeroSpatialCore

final class CommandGateTests: XCTestCase {
    private func request(_ gate: inout GimbalCommandGate, at now: Double = 10)
        -> CommandAdmission {
        gate.request(now: now, pitch: -25, authorized: true, connected: true,
                     aircraftFlying: false, headTimestamp: now - 0.1,
                     telemetryTimestamp: now - 0.1)
    }

    func testAdmissionPendingAndCompletion() throws {
        var gate = GimbalCommandGate()
        let ticket: CommandTicket
        switch request(&gate) {
        case .granted(let issued): ticket = issued
        default: return XCTFail("Expected an admitted command")
        }
        XCTAssertEqual(request(&gate), .blocked(.pending))
        XCTAssertEqual(gate.complete(ticket, now: 10.2, succeeded: true), .completed)
        XCTAssertNil(gate.pending)
        if case .granted = request(&gate, at: 10.4) { } else { XCTFail("Next command was blocked") }
    }

    func testTimeoutLatchesAndLateAckIsIgnored() throws {
        var gate = GimbalCommandGate()
        let ticket: CommandTicket
        switch request(&gate) {
        case .granted(let issued): ticket = issued
        default: return XCTFail("Expected admission")
        }
        XCTAssertTrue(gate.checkTimeout(now: 11.1))
        XCTAssertEqual(gate.complete(ticket, now: 11.2, succeeded: true), .ignored)
        XCTAssertEqual(request(&gate, at: 11.2), .blocked(.faultLatched))
        gate.reset()
        XCTAssertEqual(gate.complete(ticket, now: 11.3, succeeded: true), .ignored)
        if case .granted = request(&gate, at: 11.4) { } else { XCTFail("Reset did not recover") }
    }

    func testStaleInputsAndFlightAreBlocked() {
        var gate = GimbalCommandGate()
        XCTAssertEqual(gate.request(now: 10, pitch: -25, authorized: false,
                                    connected: true, aircraftFlying: false,
                                    headTimestamp: 10, telemetryTimestamp: 10), .blocked(.notAuthorized))
        XCTAssertEqual(gate.request(now: 10, pitch: -25, authorized: true,
                                    connected: true, aircraftFlying: true,
                                    headTimestamp: 10, telemetryTimestamp: 10), .blocked(.aircraftFlying))
        XCTAssertEqual(gate.request(now: 10, pitch: -25, authorized: true,
                                    connected: true, aircraftFlying: false,
                                    headTimestamp: 8, telemetryTimestamp: 10), .blocked(.headStale))
        XCTAssertEqual(gate.request(now: 10, pitch: -25, authorized: true,
                                    connected: true, aircraftFlying: false,
                                    headTimestamp: 10, telemetryTimestamp: 7), .blocked(.telemetryStale))
        XCTAssertEqual(gate.request(now: .nan, pitch: -25, authorized: true,
                                    connected: true, aircraftFlying: false,
                                    headTimestamp: 10, telemetryTimestamp: 10), .blocked(.invalidInput))
    }

    func testFailureLatchesUntilExplicitReset() {
        var gate = GimbalCommandGate()
        if case .granted(let ticket) = request(&gate) {
            XCTAssertEqual(gate.complete(ticket, now: 10.1, succeeded: false), .rejected)
        } else { XCTFail("Expected admission") }
        XCTAssertEqual(request(&gate, at: 10.3), .blocked(.faultLatched))
    }
}
