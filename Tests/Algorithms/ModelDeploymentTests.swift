import XCTest
@testable import AeroSpatialCore

final class ModelDeploymentTests: XCTestCase {
    func testSharedContractAndConservativeSelection() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/models.json")
        let models = try JSONDecoder().decode([ModelDeployment].self, from: Data(contentsOf: url))
        XCTAssertEqual(models.count, 1)
        var catalog = ModelDeploymentCatalog()
        XCTAssertTrue(catalog.register(models[0]))
        XCTAssertFalse(catalog.register(models[0]))
        XCTAssertNil(catalog.choose("scene-detector", supported: [.native],
                                    availableMemoryBytes: 1 << 30, deadlineMilliseconds: 60))
        XCTAssertNil(catalog.choose("scene-detector", supported: [.coreml],
                                    availableMemoryBytes: 1024, deadlineMilliseconds: 60))
        XCTAssertEqual(catalog.choose("scene-detector", supported: [.coreml],
                                     availableMemoryBytes: 1 << 30,
                                     deadlineMilliseconds: 60), models[0])
    }

    func testRejectUnsafeFilenameAndDigest() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/models.json")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])[0]
        object["relativePath"] = "../evil.bin"
        let unsafe = try JSONDecoder().decode(ModelDeployment.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertFalse(unsafe.validate())
        object["relativePath"] = "model.bin"
        object["sha256"] = "not-a-digest"
        let wrongHash = try JSONDecoder().decode(ModelDeployment.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertFalse(wrongHash.validate())
    }
}
