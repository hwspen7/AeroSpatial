import Foundation
import XCTest
@testable import AeroSpatialCore

final class SegmentJournalTests: XCTestCase {
    func testRotationAndCorruptTailRepair() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = try SegmentJournal(directory: root, segmentBytes: 1024, maximumSegments: 3)
        for count in 0..<6 {
            try await journal.append(Data(repeating: UInt8(count), count: 400))
        }
        let path = root.appendingPathComponent("segment-00000002.bin")
        let damaged = try FileHandle(forWritingTo: path)
        try damaged.seekToEnd()
        try damaged.write(contentsOf: Data([2, 3]))
        try damaged.close()
        _ = try SegmentJournal(directory: root, segmentBytes: 1024, maximumSegments: 3)
        let attributes = try FileManager.default.attributesOfItem(atPath: path.path)
        XCTAssertEqual(attributes[.size] as? Int, 816)
        do {
            try await journal.append(Data(repeating: 1, count: 400))
            XCTFail("Expected bounded journal to refuse another segment")
        } catch SegmentJournal.Failure.limitReached { }
    }
}
