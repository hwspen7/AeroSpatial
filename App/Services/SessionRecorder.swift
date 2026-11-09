import Foundation
import AeroSpatialCore

@MainActor
final class SessionRecorder {
    private var handle: FileHandle?
    private var sequence = 0
    private var lastUptime: Double?
    private var sessionId: String?
    private(set) var activeURL: URL?
    private(set) var lastSavedURL: URL?
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    func start() throws -> URL {
        if handle != nil { stop() }
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AeroSpatialSessions", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let suffix = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let path = folder.appendingPathComponent("flight-\(suffix)-\(UUID().uuidString.prefix(8)).jsonl")
        guard FileManager.default.createFile(atPath: path.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        handle = try FileHandle(forWritingTo: path)
        sequence = 0
        lastUptime = nil
        sessionId = UUID().uuidString
        activeURL = path
        return path
    }

    func write(_ record: SessionRecord) throws {
        guard let handle = handle, let sessionId = sessionId else { return }
        guard EventContract.accepts(record),
              lastUptime.map({ record.uptime >= $0 }) ?? true else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        var versioned = record
        versioned.schemaVersion = 1
        versioned.sessionId = sessionId
        versioned.sequence = sequence
        guard EventContract.accepts(versioned) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        let data = try encoder.encode(versioned)
        guard data.count <= EventContract.maximumLineBytes else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        try handle.write(contentsOf: data + Data([0x0A]))
        sequence += 1
        lastUptime = record.uptime
    }

    func stop() {
        try? handle?.synchronize()
        try? handle?.close()
        handle = nil
        sessionId = nil
        sequence = 0
        lastUptime = nil
        if let url = activeURL { lastSavedURL = url }
        activeURL = nil
    }
}
