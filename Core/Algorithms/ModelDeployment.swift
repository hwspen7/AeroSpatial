import Foundation

/// Read-only model declaration used for local device planning. Execution is separate.
/// A SHA-256 digest only proves byte identity, not model publisher authenticity.
public struct ModelDeployment: Codable, Equatable, Sendable {
    public enum Backend: String, Codable, CaseIterable, Sendable {
        case coreml, onnx, tflite, native
    }
    public let identifier: String
    public let revision: String
    public let backend: Backend
    public let relativePath: String
    public let sha256: String
    public let memoryBytes: UInt64
    public let typicalLatencyMs: Double
    public let inputStream: SpatialStream
    public let outputStream: SpatialStream

    public func validate() -> Bool {
        let idPattern = #"^[a-z][a-z0-9_-]{2,63}$"#
        let revisionPattern = #"^[0-9]+\.[0-9]+\.[0-9]+$"#
        let digestPattern = #"^[0-9a-f]{64}$"#
        guard identifier.range(of: idPattern, options: .regularExpression) != nil,
              revision.range(of: revisionPattern, options: .regularExpression) != nil,
              sha256.range(of: digestPattern, options: .regularExpression) != nil,
              relativePath != ".", relativePath != "..",
              relativePath.utf8.count > 0, relativePath.utf8.count <= 255,
              !relativePath.contains("/"), !relativePath.contains("\\"),
              (1...8_589_934_592).contains(memoryBytes),
              typicalLatencyMs.isFinite, typicalLatencyMs > 0, typicalLatencyMs <= 60000,
              [.perception, .diagnostic].contains(outputStream) else { return false }
        return true
    }
}

/// Conservative planner. Passing this gate never launches or trusts a model.
public struct ModelDeploymentCatalog: Sendable {
    private var entries: [String: ModelDeployment] = [:]
    public init() {}

    public mutating func register(_ model: ModelDeployment) -> Bool {
        let key = model.identifier + "@" + model.revision
        guard model.validate(), entries[key] == nil, entries.count < 256 else { return false }
        entries[key] = model
        return true
    }

    public func choose(_ identifier: String, supported: Set<ModelDeployment.Backend>,
                       availableMemoryBytes: UInt64, deadlineMilliseconds: Double) -> ModelDeployment? {
        guard deadlineMilliseconds.isFinite && deadlineMilliseconds >= 0 else { return nil }
        return entries.values.filter { model in
            model.identifier == identifier && supported.contains(model.backend) &&
            model.memoryBytes <= availableMemoryBytes && model.typicalLatencyMs <= deadlineMilliseconds
        }.sorted { a, b in
            if a.typicalLatencyMs != b.typicalLatencyMs { return a.typicalLatencyMs < b.typicalLatencyMs }
            if a.memoryBytes != b.memoryBytes { return a.memoryBytes < b.memoryBytes }
            return a.revision < b.revision
        }.first
    }
}
