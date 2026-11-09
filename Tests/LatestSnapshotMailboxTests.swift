import Foundation
import XCTest
@testable import AeroSpatialCore

final class LatestSnapshotMailboxTests: XCTestCase {
    func testLatestValueAndBoundedMemory() {
        let mailbox = LatestSnapshotMailbox<Int>()
        for i in 0..<10000 { mailbox.offer(i) }
        XCTAssertEqual(mailbox.takeLatest(), 9999)
        XCTAssertNil(mailbox.takeLatest())
        XCTAssertEqual(mailbox.counters.received, 10000)
        XCTAssertEqual(mailbox.counters.superseded, 9999)
    }

    func testConcurrentWriterReader() {
        let mailbox = LatestSnapshotMailbox<Int>()
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "mailbox-test", attributes: .concurrent)
        for value in 0..<1000 {
            group.enter()
            queue.async { mailbox.offer(value); group.leave() }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 10), .success)
        XCTAssertEqual(mailbox.counters.received, 1000)
        XCTAssertNotNil(mailbox.takeLatest())
    }
}
