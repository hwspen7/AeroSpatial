import AeroSpatialCore
import Foundation

/// SessionArchive is the sole durable store. JSONL is exported after successful
/// flush and CRC verification. Sensor callbacks only admit bounded work.
@MainActor
final class SessionRecorder {
    enum Failure: Error { case queueFull, inactiveSession, invalidEvent }

    private let admission = DispatchSemaphore(value: 512)
    private var continuation: AsyncStream<SessionRecord>.Continuation?
    private var worker: Task<Result<URL, Error>, Never>?
    private var closing = false
    private var lastAdmittedUptime: Double?
    var onWriteFailure: ((Error) -> Void)?
    private(set) var activeURL: URL?
    private(set) var lastSavedURL: URL?

    func start() throws -> URL {
        guard continuation == nil, !closing else { throw Failure.inactiveSession }
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AeroSpatialSessions", isDirectory: true)
        let name = "session-\(UUID().uuidString)"
        let folder = base.appendingPathComponent(name, isDirectory: true)
        let exported = folder.appendingPathComponent("flight.jsonl")
        let archive = try SessionArchive(directory: folder)
        var owner: AsyncStream<SessionRecord>.Continuation?
        let stream = AsyncStream<SessionRecord>(bufferingPolicy: .unbounded) { owner = $0 }
        guard let owner else { throw Failure.inactiveSession }
        let capacity = admission
        let reportFailure: @Sendable (Error) -> Void = { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self, self.activeURL == exported, !self.closing else { return }
                self.onWriteFailure?(error)
            }
        }
        worker = Task.detached(priority: .utility) {
            var firstError: Error?
            for await record in stream {
                defer { capacity.signal() }
                guard firstError == nil else { continue }
                do { try await archive.append(record) }
                catch {
                    firstError = error
                    reportFailure(error)
                }
            }
            if let firstError { return .failure(firstError) }
            do { return .success(try await archive.exportJSONL(to: exported)) }
            catch {
                reportFailure(error)
                return .failure(error)
            }
        }
        continuation = owner
        activeURL = exported
        lastAdmittedUptime = nil
        return exported
    }

    /// A nonblocking capacity check guarantees at most 512 outstanding records.
    func write(_ record: SessionRecord) throws {
        guard let continuation, !closing else { throw Failure.inactiveSession }
        guard EventContract.accepts(record),
              lastAdmittedUptime.map({ record.uptime >= $0 }) ?? true else {
            throw Failure.invalidEvent
        }
        guard admission.wait(timeout: .now()) == .success else { throw Failure.queueFull }
        switch continuation.yield(record) {
        case .enqueued:
            lastAdmittedUptime = record.uptime
        case .dropped, .terminated:
            admission.signal()
            throw Failure.queueFull
        @unknown default:
            admission.signal()
            throw Failure.queueFull
        }
    }

    func stop(completion: @escaping @MainActor (Result<URL, Error>) -> Void) {
        guard let continuation, let worker else { return }
        closing = true
        self.continuation = nil
        continuation.finish()
        Task {
            let result = await worker.value
            self.worker = nil
            self.closing = false
            self.activeURL = nil
            self.lastAdmittedUptime = nil
            if case .success(let path) = result { self.lastSavedURL = path }
            completion(result)
        }
    }
}
