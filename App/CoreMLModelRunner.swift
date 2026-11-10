#if canImport(CoreML) && canImport(CryptoKit)
import CoreML
import CryptoKit
import Foundation
import AeroSpatialCore

/// Optional trusted on-device Core ML loader. Inference is read-only: results
/// never enter the aircraft command gate. Keep all calls off the UI thread.
final class CoreMLModelRunner {
    enum Failure: Error {
        case invalidManifest, unsafePath, changedArtifact
    }

    let declaration: ModelDeployment
    private let model: MLModel

    init(root: URL, declaration: ModelDeployment) throws {
        guard declaration.validate(), declaration.backend == .coreml,
              declaration.relativePath.hasSuffix(".mlmodel"),
              root.isFileURL, root.hasDirectoryPath else { throw Failure.invalidManifest }
        let base = root.standardizedFileURL.resolvingSymlinksInPath()
        let file = base.appendingPathComponent(declaration.relativePath)
        guard file.deletingLastPathComponent().resolvingSymlinksInPath() == base,
              file.standardizedFileURL.resolvingSymlinksInPath() == file.standardizedFileURL else {
            throw Failure.unsafePath
        }
        let bytes = try Data(contentsOf: file, options: .mappedIfSafe)
        let digest = SHA256.hash(data: bytes)
            .map { String(format: "%02x", $0) }.joined()
        guard digest == declaration.sha256 else { throw Failure.changedArtifact }
        let compiled = try MLModel.compileModel(at: file)
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        model = try MLModel(contentsOf: compiled, configuration: configuration)
        self.declaration = declaration
    }

    /// Actual Core ML forward pass; caller owns scheduling and model-specific
    /// interpretation. Neither outputs nor declared latency prove accuracy.
    func predict(_ features: MLFeatureProvider) throws -> MLFeatureProvider {
        try model.prediction(from: features)
    }
}
#endif
