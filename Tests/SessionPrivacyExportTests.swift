import Foundation
import XCTest
@testable import AeroSpatialCore

final class SessionPrivacyExportTests: XCTestCase {
    private func setup() throws -> (URL, URL, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return (root, root.appendingPathComponent("raw.jsonl"), root.appendingPathComponent("shared.jsonl"))
    }

    private func write(_ events: [SessionRecord], to path: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var data = Data()
        for item in events {
            data.append(try encoder.encode(item))
            data.append(0x0A)
        }
        try data.write(to: path)
    }

    func testSanitizedExportDropsCoordinatesNotesOriginalTimesAndUnknownNumericFields() throws {
        let (root, source, output) = try setup()
        defer { try? FileManager.default.removeItem(at: root) }
        let records = (0..<3).map { index in
            SessionRecord(wallTime: Date(timeIntervalSince1970: 1_800_000_000 + Double(index)),
                          uptime: 500 + Double(index), kind: "telemetry", source: "dji",
                          fields: ["latitude": 40, "longitude": -83,
                                   "sensor_uptime": 500 + Double(index),
                                   "private_code": 12345, "battery_percent": 90 - Double(index)],
                          note: "secret location", schemaVersion: 1,
                          sessionId: "real-session", sequence: index)
        }
        try write(records, to: source)
        XCTAssertEqual(try SessionPrivacyExport.prepare(source: source, destination: output), 3)
        let result = try String(contentsOf: output, encoding: .utf8)
        XCTAssertFalse(result.contains("latitude"))
        XCTAssertFalse(result.contains("longitude"))
        XCTAssertFalse(result.contains("private_code"))
        XCTAssertFalse(result.contains("secret location"))
        XCTAssertFalse(result.contains("real-session"))
        XCTAssertFalse(result.contains("1800000000"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let items = try result.split(separator: "\n")
            .map { try decoder.decode(SessionRecord.self, from: Data($0.utf8)) }
        XCTAssertEqual(items.map(\.uptime), [0, 1, 2])
        XCTAssertEqual(items.map(\.sequence), [0, 1, 2])
        XCTAssertTrue(items.allSatisfy { $0.sessionId?.hasPrefix("anon-") == true })
        XCTAssertTrue(items.allSatisfy { $0.note == nil && $0.fields.count == 1 })
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8).contains("real-session"), true)
        XCTAssertThrowsError(try SessionPrivacyExport.prepare(source: source, destination: output))
    }

    func testRejectsTruncatedOrUnorderedSessionWithoutLeakingPartialOutput() throws {
        let (root, source, output) = try setup()
        defer { try? FileManager.default.removeItem(at: root) }
        try write([
            SessionRecord(uptime: 5, kind: "head", source: "simulator", schemaVersion: 1,
                          sessionId: "original", sequence: 0),
            SessionRecord(uptime: 4, kind: "head", source: "simulator", schemaVersion: 1,
                          sessionId: "original", sequence: 1)
        ], to: source)
        XCTAssertThrowsError(try SessionPrivacyExport.prepare(source: source, destination: output))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        try Data("{\"incomplete\":true}".utf8).write(to: source)
        XCTAssertThrowsError(try SessionPrivacyExport.prepare(source: source, destination: output))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    func testEmptyAndOversizedSessionsRejected() throws {
        let (root, source, output) = try setup()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data().write(to: source)
        XCTAssertThrowsError(try SessionPrivacyExport.prepare(source: source, destination: output))
        try Data(repeating: 65, count: EventContract.maximumLineBytes + 128).write(to: source)
        XCTAssertThrowsError(try SessionPrivacyExport.prepare(source: source, destination: output))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }
}
