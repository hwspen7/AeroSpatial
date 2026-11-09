import Foundation
import XCTest
@testable import AeroSpatialCore

final class SessionArchiveTests: XCTestCase {
    func testDurableExportAndRecovery() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = try SessionArchive(directory: root, segmentBytes: 1024, maximumSegments: 5)
        for i in 0..<6 {
            try await journal.append(SessionRecord(uptime: Double(i), kind: "head", source: "simulator",
                                                   fields: ["yaw": Double(i)]))
        }
        let exported = root.appendingPathComponent("session.jsonl")
        _ = try await journal.exportJSONL(to: exported)
        let lines = try String(contentsOf: exported, encoding: .utf8)
            .split(separator: "\n")
        XCTAssertEqual(lines.count, 6)
        for (index, line) in lines.enumerated() {
            let event = try JSONDecoder.withISO8601.decode(SessionRecord.self, from: Data(line.utf8))
            XCTAssertEqual(event.sequence, index)
            XCTAssertEqual(event.schemaVersion, 1)
        }
        do {
            _ = try await journal.exportJSONL(to: exported)
            XCTFail("Expected overwrite protection")
        } catch SessionArchive.Failure.exportExists { }
    }

    func testInvalidEventDoesNotConsumeSequence() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = try SessionArchive(directory: root, segmentBytes: 1024)
        try await journal.append(SessionRecord(uptime: 1, kind: "head", source: "simulator"))
        do {
            try await journal.append(SessionRecord(uptime: 0, kind: "head", source: "simulator"))
            XCTFail("Expected timestamp regression to fail")
        } catch SessionArchive.Failure.invalidEvent { }
        try await journal.append(SessionRecord(uptime: 2, kind: "head", source: "simulator"))
        let path = root.appendingPathComponent("out.jsonl")
        _ = try await journal.exportJSONL(to: path)
        let events = try String(contentsOf: path, encoding: .utf8).split(separator: "\n")
        XCTAssertEqual(events.count, 2)
        let last = try JSONDecoder.withISO8601.decode(SessionRecord.self, from: Data(events[1].utf8))
        XCTAssertEqual(last.sequence, 1)
    }

    func testEarlierSegmentTruncationRejectedWithoutDataLoss() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = try SegmentJournal(directory: root, segmentBytes: 1024, maximumSegments: 4)
        for _ in 0..<5 { try await journal.append(Data(repeating: 9, count: 400)) }
        let first = root.appendingPathComponent("segment-00000000.bin")
        let handle = try FileHandle(forUpdating: first)
        try handle.truncate(atOffset: 407)
        try handle.close()
        do {
            _ = try SegmentJournal(directory: root, segmentBytes: 1024, maximumSegments: 4)
            XCTFail("Earlier segment corruption must not be truncated")
        } catch SegmentRecovery.Failure.invalidSegment { }
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: first.path)[.size]) as? Int, 407)
    }

    func testRestartRecoveryExportsOnlyCompleteRecords() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = try SessionArchive(directory: root, segmentBytes: 1024)
        try await journal.append(SessionRecord(uptime: 1, kind: "head", source: "simulator"))
        try await journal.append(SessionRecord(uptime: 2, kind: "head", source: "simulator"))
        let tail = root.appendingPathComponent("segment-00000000.bin")
        let file = try FileHandle(forWritingTo: tail)
        try file.seekToEnd()
        try file.write(contentsOf: Data([0x30, 0x01, 0x00]))
        try file.close()
        let exported = root.appendingPathComponent("recovered.jsonl")
        _ = try SessionArchive.recover(directory: root, to: exported, segmentBytes: 1024)
        XCTAssertEqual(try String(contentsOf: exported, encoding: .utf8)
            .split(separator: "\n").count, 2)
    }

    func testChecksumCorruptionRejectedRatherThanRepaired() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = try SegmentJournal(directory: root, segmentBytes: 1024)
        try await journal.append(Data(repeating: 7, count: 64))
        let path = root.appendingPathComponent("segment-00000000.bin")
        let handle = try FileHandle(forUpdating: path)
        try handle.seek(toOffset: 8)
        try handle.write(contentsOf: Data([4]))
        try handle.close()
        do {
            _ = try SegmentJournal(directory: root, segmentBytes: 1024)
            XCTFail("CRC mismatch must not be silently truncated")
        } catch SegmentRecovery.Failure.invalidSegment { }
    }
}

private extension JSONDecoder {
    static var withISO8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
