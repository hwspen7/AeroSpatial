import XCTest
@testable import AeroSpatialCore

final class PipelineSpanTests: XCTestCase {
    func testValidatedRoundTrip() throws {
        let source = try XCTUnwrap(PipelineSpan(traceId: 7, spanId: 3, parentId: 2,
                                               clockDomain: 1, startNs: 100, endNs: 210,
                                               name: "frame_decode"))
        XCTAssertEqual(source.durationNanoseconds, 110)
        XCTAssertEqual(try JSONDecoder().decode(PipelineSpan.self,
                                                from: JSONEncoder().encode(source)), source)
    }

    func testInvalidMetadataRejectedAtDecode() throws {
        XCTAssertNil(PipelineSpan(traceId: 0, spanId: 1, parentId: nil,
                                  clockDomain: 1, startNs: 20, endNs: 10, name: "decode"))
        let bad = """
        {"traceId":1,"spanId":2,"parentId":2,"clockDomain":1,
         "startNs":30,"endNs":20,"name":"bad_name","outcome":"ok"}
        """
        XCTAssertThrowsError(try JSONDecoder().decode(PipelineSpan.self, from: Data(bad.utf8)))
    }
}
