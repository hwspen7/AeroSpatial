import Foundation

/// Causal timing metadata. All values share an explicit monotonic clock domain.
/// Spans do not imply flight command success or an end-to-end latency guarantee.
public struct PipelineSpan: Codable, Equatable, Sendable {
    public let traceId: UInt64
    public let spanId: UInt64
    public let parentId: UInt64?
    public let clockDomain: UInt32
    public let startNs: UInt64
    public let endNs: UInt64
    public let name: String
    public let outcome: String

    public init?(traceId: UInt64, spanId: UInt64, parentId: UInt64?,
                 clockDomain: UInt32, startNs: UInt64, endNs: UInt64,
                 name: String, outcome: String = "ok") {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789_-")
        let initials = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz")
        guard traceId > 0, spanId > 0, clockDomain > 0,
              parentId != spanId, endNs >= startNs, (2...64).contains(name.utf8.count),
              name.unicodeScalars.first.map({ initials.contains($0) }) == true,
              name.unicodeScalars.allSatisfy({ allowed.contains($0) }),
              ["ok", "error", "dropped", "skipped"].contains(outcome) else { return nil }
        self.traceId = traceId
        self.spanId = spanId
        self.parentId = parentId
        self.clockDomain = clockDomain
        self.startNs = startNs
        self.endNs = endNs
        self.name = name
        self.outcome = outcome
    }

    public var durationNanoseconds: UInt64 { endNs - startNs }

    private enum CodingKeys: String, CodingKey {
        case traceId, spanId, parentId, clockDomain, startNs, endNs, name, outcome
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let valid = try Self(
            traceId: c.decode(UInt64.self, forKey: .traceId),
            spanId: c.decode(UInt64.self, forKey: .spanId),
            parentId: c.decodeIfPresent(UInt64.self, forKey: .parentId),
            clockDomain: c.decode(UInt32.self, forKey: .clockDomain),
            startNs: c.decode(UInt64.self, forKey: .startNs),
            endNs: c.decode(UInt64.self, forKey: .endNs),
            name: c.decode(String.self, forKey: .name),
            outcome: c.decode(String.self, forKey: .outcome)) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Invalid causal span"))
        }
        self = valid
    }
}
