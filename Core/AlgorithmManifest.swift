import Foundation

/// Declarative algorithm contract. A manifest never grants aircraft control.
public struct AlgorithmManifest: Codable, Equatable, Sendable {
    public let identifier: String
    public let inputs: [SpatialStream]
    public let outputs: [SpatialStream]
    public let dependencies: [String]
    public let memoryBudgetBytes: UInt64
    public let deadlineMilliseconds: UInt32
    public let deterministic: Bool
    public let requiresHardware: Bool

    public func validate() throws {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789_-")
        guard (3...64).contains(identifier.utf8.count),
              identifier.unicodeScalars.first.map({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz").contains($0) }) == true,
              identifier.unicodeScalars.allSatisfy({ allowed.contains($0) }),
              !inputs.isEmpty, !outputs.isEmpty,
              Set(inputs).count == inputs.count, Set(outputs).count == outputs.count,
              Set(outputs).isSubset(of: [.perception, .diagnostic]),
              (1...536_870_912).contains(memoryBudgetBytes),
              (1...10_000).contains(deadlineMilliseconds),
              Set(dependencies).count == dependencies.count,
              !dependencies.contains(identifier),
              dependencies.allSatisfy({ (3...64).contains($0.utf8.count) &&
                  $0.unicodeScalars.first.map({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz").contains($0) }) == true &&
                  $0.unicodeScalars.allSatisfy({ allowed.contains($0) }) }) else {
            throw AlgorithmRegistryError.invalidManifest
        }
    }
}

public enum AlgorithmRegistryError: Error, Equatable {
    case invalidManifest
    case duplicateIdentifier
    case missingDependency(String)
    case dependencyCycle
}
