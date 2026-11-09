import Foundation
import XCTest
@testable import AeroSpatialCore

final class SegmentJournalSinkTests: XCTestCase {
    func testOrderedBackgroundWritesSurviveRestart() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let sink = try SegmentJournalSink(directory: folder, pendingBudgetBytes: 32768,
                                           segmentBytes: 4096, maximumSegments: 8)
        for index in 0..<64 {
            let text = String(format: "event-%03d", index)
            try sink.submit(Data(text.utf8))
        }
        try sink.close()
        XCTAssertEqual(sink.queuedBytes, 0)
        XCTAssertThrowsError(try sink.submit(Data("closed".utf8)))
        let segments = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        XCTAssertTrue(segments.contains("segment-00000000.bin"))
        let recovered = try SegmentRecovery.repair(
            folder.appendingPathComponent("segment-00000000.bin"), maximumBytes: 4096)
        XCTAssertGreaterThan(recovered, 0)
        // Actor initializer must scan the existing journal without corrupting it.
        let reopened = try SegmentJournalSink(directory: folder, segmentBytes: 4096)
        try reopened.submit(Data("after-restart".utf8))
        try reopened.close()
    }

    func testQueueRejectsOversizeWithoutBlocking() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let sink = try SegmentJournalSink(directory: folder, pendingBudgetBytes: 1024,
                                          segmentBytes: 2048)
        XCTAssertThrowsError(try sink.submit(Data(repeating: 9, count: 1025)))
        try sink.close()
    }
}
