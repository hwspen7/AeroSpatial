import Foundation
import AeroSpatialCore

/// Asynchronous, CRC-framed local recording. Filesystem writes and fsync happen
/// on the utility queue, not in the UI/sensor callback. Backpressure is explicit.
@MainActor
final class SessionRecorder {
    private var sink: SegmentJournalSink?
    private var sequence = 0
    private var lastUptime: Double?
    private var sessionId: String?
    private(set) var activeURL: URL?
    private(set) var lastSavedURL: URL?
    private(set) var lastFailure: String?
    var queuedBytes: Int? { sink?.queuedBytes }
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    func start() throws -> URL {
        if sink != nil { stop() }
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AeroSpatialSessions", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = "flight-\(UUID().uuidString)"
        let path = folder.appendingPathComponent(name, isDirectory: true)
        sink = try SegmentJournalSink(directory: path)
        sessionId = UUID().uuidString
        sequence = 0
        lastUptime = nil
        lastFailure = nil
        activeURL = path
        return path
    }

    func write(_ record: SessionRecord) throws {
        guard let sink, let sessionId else { return }
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
        try sink.submit(data)
        sequence += 1
        lastUptime = record.uptime
    }

    func stop() {
        guard let sink else { return }
        do {
            try sink.close()
            lastSavedURL = activeURL
        } catch {
            lastFailure = String(describing: error)
            lastSavedURL = nil
        }
        self.sink = nil
        activeURL = nil
        sessionId = nil
        sequence = 0
        lastUptime = nil
    }
}
