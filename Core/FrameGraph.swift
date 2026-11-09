import Foundation

/// Explicit coordinate frames. Unknown relationships remain unknown.
public struct FrameIdentifier: Hashable, Codable, Sendable {
    public let value: String

    public init?(_ value: String) {
        guard !value.isEmpty, value.count <= 64,
              value.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") })
        else { return nil }
        self.value = value
    }
}

/// A bounded graph of static or currently calibrated transforms.
/// Dynamic transforms must be updated explicitly after acquiring new observations.
public struct FrameGraph: Sendable {
    private var edges: [FrameIdentifier: [FrameIdentifier: SpatialTransform]] = [:]
    public var maximumFrames = 64

    public init() {}

    /// Parent and child frames refer to a transform mapping child -> parent.
    @discardableResult
    public mutating func link(parent: FrameIdentifier, child: FrameIdentifier,
                              transform: SpatialTransform) -> Bool {
        let newFrames = (edges[parent] == nil ? 1 : 0) + (edges[child] == nil ? 1 : 0)
        guard parent != child, maximumFrames >= 2,
              edges.count + newFrames <= maximumFrames,
              let inverse = transform.inverted() else { return false }
        // Reject conflicting alternative paths; a caller must remove an old calibration first.
        if resolve(from: child, to: parent) != nil { return false }
        edges[parent, default: [:]][child] = inverse
        edges[child, default: [:]][parent] = transform
        return true
    }

    public mutating func remove(parent: FrameIdentifier, child: FrameIdentifier) {
        edges[parent]?[child] = nil
        edges[child]?[parent] = nil
        if edges[parent]?.isEmpty == true { edges[parent] = nil }
        if edges[child]?.isEmpty == true { edges[child] = nil }
    }

    /// Transforms a point in `from` into `to`; returns nil if no calibrated path exists.
    public func resolve(from: FrameIdentifier, to: FrameIdentifier) -> SpatialTransform? {
        if from == to { return .identity }
        var visited: Set<FrameIdentifier> = [from]
        var queue: [(FrameIdentifier, SpatialTransform)] = [(from, .identity)]
        var index = 0
        while index < queue.count {
            let (frame, mapping) = queue[index]
            index += 1
            let neighbors = (edges[frame] ?? [:]).sorted { $0.key.value < $1.key.value }
            for (next, transform) in neighbors where !visited.contains(next) {
                guard let composed = transform.composed(with: mapping) else { continue }
                if next == to { return composed }
                visited.insert(next)
                queue.append((next, composed))
            }
        }
        return nil
    }
}
