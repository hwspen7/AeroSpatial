import Foundation

/// Deterministic dependency planner for metadata-only algorithm registration.
/// Actual model loading, process isolation, and permission enforcement are separate.
public struct AlgorithmRegistry: Sendable {
    private var manifests: [String: AlgorithmManifest] = [:]
    public init() {}

    public var count: Int { manifests.count }

    public mutating func register(_ manifest: AlgorithmManifest) throws {
        try manifest.validate()
        guard manifests.count < 256 else { throw AlgorithmRegistryError.invalidManifest }
        guard manifests[manifest.identifier] == nil else {
            throw AlgorithmRegistryError.duplicateIdentifier
        }
        manifests[manifest.identifier] = manifest
    }

    public func executionPlan() throws -> [AlgorithmManifest] {
        var visited: Set<String> = []
        var active: Set<String> = []
        var result: [AlgorithmManifest] = []

        func visit(_ identifier: String) throws {
            guard let algorithm = manifests[identifier] else {
                throw AlgorithmRegistryError.missingDependency(identifier)
            }
            if visited.contains(identifier) { return }
            guard active.insert(identifier).inserted else {
                throw AlgorithmRegistryError.dependencyCycle
            }
            for dependency in algorithm.dependencies.sorted() {
                try visit(dependency)
                guard let parent = manifests[dependency],
                      !Set(parent.outputs).isDisjoint(with: Set(algorithm.inputs)) else {
                    throw AlgorithmRegistryError.invalidManifest
                }
            }
            active.remove(identifier)
            visited.insert(identifier)
            result.append(algorithm)
        }
        for id in manifests.keys.sorted() { try visit(id) }
        return result
    }
}
