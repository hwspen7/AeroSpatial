import Foundation
import AeroSpatialCore

/// Bounded asynchronous JSONL recording. File I/O never runs in a sensor callback.
/// Each session's writes and fsync execute in one serial background queue.
@MainActor
final class SessionRecorder {
    enum Failure: Error { case queueFull, inactiveSession, invalidEvent }

    private var handle: FileHandle?
    private var sequence = 0
    private var lastUptime: Double?
    private var sessionId: String?
    private let queue = DispatchQueue(label: "AeroSpatial.SessionRecorder", qos: .utility)
    private let capacity = DispatchSemaphore(value: 512)
    var onWriteFailure: ((Error) -> Void)?
    private(set) var activeURL: URL?
    private(set) var lastSavedURL: URL?
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    func start() throws -> URL {
        guard handle == nil else { throw Failure.inactiveSession }
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

    /// Admission is synchronous and bounded; actual disk operations are off-main.
    func write(_ record: SessionRecord) throws {
        guard let handle, let sessionId else { throw Failure.inactiveSession }
        guard EventContract.accepts(record),
              lastUptime.map({ record.uptime >= $0 }) ?? true else { throw Failure.invalidEvent }
        var versioned = record
        versioned.schemaVersion = 1
        versioned.sessionId = sessionId
        versioned.sequence = sequence
        guard EventContract.accepts(versioned) else { throw Failure.invalidEvent }
        let encoded = try encoder.encode(versioned)
        guard encoded.count <= EventContract.maximumLineBytes else { throw Failure.invalidEvent }
        guard capacity.wait(timeout: .now()) == .success else { throw Failure.queueFull }
        sequence += 1
        lastUptime = record.uptime
        let onError = onWriteFailure
        let id = sessionId
        let admission = capacity
        queue.async {
            defer { admission.signal() }
            do { try handle.write(contentsOf: encoded + Data([0x0A])) }
            catch { Task { @MainActor [weak self] in
                guard self?.sessionId == id else { return }
                onError?(error)
            } }
        }
    }

    /// Completion is delivered only after all earlier writes are flushed and closed.
    func stop(completion: @escaping @MainActor (Result<URL, Error>) -> Void) {
        guard let handle, let url = activeURL else { return }
        self.handle = nil
        self.sessionId = nil
        self.sequence = 0
        self.lastUptime = nil
        self.activeURL = nil
        queue.async {
            let outcome: Result<URL, Error>
            do {
                try handle.synchronize()
                try handle.close()
                outcome = .success(url)
            } catch {
                outcome = .failure(error)
            }
            Task { @MainActor in completion(outcome) }
        }
    }
}
