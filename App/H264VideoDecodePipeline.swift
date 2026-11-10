import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox
import AeroSpatialCore

/// Serial iOS boundary between the portable C++ access-unit assembler and
/// VideoToolbox. Encoded input is an AVCC picture, not a decoded pixel buffer.
/// This pipeline does not execute flight commands or manufacture camera PTS.
final class H264VideoDecodePipeline: @unchecked Sendable {
    struct Counters: Sendable {
        let submitted: UInt64
        let decoded: UInt64
        let rejected: UInt64
        let queueDropped: UInt64
        let pending: Int
    }

    private let queue = DispatchQueue(label: "AeroSpatial.VideoToolbox.Decoder", qos: .userInitiated)
    private let lock = NSLock()
    private var pending = 0
    private var submitted: UInt64 = 0
    private var decoded: UInt64 = 0
    private var rejected: UInt64 = 0
    private var dropped: UInt64 = 0
    private let maximumPending = 4
    private let decoder = VideoToolboxDecoder()
    private var activeParameterSets: (sps: Data, pps: Data)?
    private var format: CMFormatDescription?
    private var awaitingKeyframe = true
    private var generation: UInt64 = 0

    /// The callback runs on the serial video worker and must return promptly.
    /// Pixel-buffer consumers must retain the buffer if they need it afterward.
    var onDecodedFrame: ((CVPixelBuffer, CMTime) -> Void)?

    func markDiscontinuity() {
        queue.async { [self] in
            generation &+= 1
            awaitingKeyframe = true
            activeParameterSets = nil
            format = nil
            decoder.shutdown()
        }
    }

    func accept(_ unit: H264AccessUnit, receivedAtNanoseconds: UInt64) {
        lock.lock()
        guard pending < maximumPending, unit.avcc.count <= 8 * 1024 * 1024,
              receivedAtNanoseconds > 0, receivedAtNanoseconds <= UInt64(Int64.max) else {
            dropped &+= 1
            lock.unlock()
            // A dropped interdependent picture requires decoder resynchronization.
            markDiscontinuity()
            return
        }
        pending += 1
        lock.unlock()
        queue.async { [self] in
            defer {
                lock.lock()
                pending -= 1
                lock.unlock()
            }
            do {
                if activeParameterSets?.sps != unit.sps || activeParameterSets?.pps != unit.pps {
                    generation &+= 1
                    awaitingKeyframe = true
                    decoder.shutdown()
                    format = try makeFormat(sps: unit.sps, pps: unit.pps)
                    activeParameterSets = (unit.sps, unit.pps)
                }
                guard !awaitingKeyframe || unit.isKeyframe else { return }
                let sample = try makeSample(avcc: unit.avcc,
                                            presentationNanoseconds: receivedAtNanoseconds)
                let currentGeneration = generation
                try decoder.decode(sample) { [weak self] pixels, time in
                    // VideoToolbox may invoke this callback on its own queue.
                    // Return to the serial worker and ignore previous sessions.
                    self?.queue.async { [weak self] in
                        guard let self, self.generation == currentGeneration else { return }
                        self.lock.lock()
                        self.decoded &+= 1
                        self.lock.unlock()
                        self.onDecodedFrame?(pixels, time)
                    }
                }
                awaitingKeyframe = false
                lock.lock()
                submitted &+= 1
                lock.unlock()
            } catch {
                generation &+= 1
                awaitingKeyframe = true
                decoder.shutdown()
                lock.lock()
                rejected &+= 1
                lock.unlock()
            }
        }
    }

    func snapshot() -> Counters {
        lock.lock()
        defer { lock.unlock() }
        return Counters(submitted: submitted, decoded: decoded,
                        rejected: rejected, queueDropped: dropped, pending: pending)
    }

    private enum Failure: Error {
        case format(OSStatus), block(OSStatus), sample(OSStatus)
        case invalidDimensions, missingFormat
    }

    /// Validates SPS/PPS using CoreMedia and obtains dimensions from the stream.
    private func makeFormat(sps: Data, pps: Data) throws -> CMFormatDescription {
        var description: CMFormatDescription?
        let status = sps.withUnsafeBytes { sb in
            pps.withUnsafeBytes { pb in
                let spsPtr = sb.bindMemory(to: UInt8.self).baseAddress!
                let ppsPtr = pb.bindMemory(to: UInt8.self).baseAddress!
                var pointers: [UnsafePointer<UInt8>] = [spsPtr, ppsPtr]
                var sizes: [Int] = [sps.count, pps.count]
                return CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault, parameterSetCount: 2,
                    parameterSetPointers: &pointers, parameterSetSizes: &sizes,
                    nalUnitHeaderLength: 4, formatDescriptionOut: &description)
            }
        }
        guard status == noErr, let format = description else { throw Failure.format(status) }
        let dimensions = CMVideoFormatDescriptionGetDimensions(format)
        guard dimensions.width > 0, dimensions.height > 0,
              dimensions.width <= 8192, dimensions.height <= 8192 else {
            throw Failure.invalidDimensions
        }
        return format
    }

    private func makeSample(avcc: Data, presentationNanoseconds: UInt64) throws -> CMSampleBuffer {
        guard let format else { throw Failure.missingFormat }
        var block: CMBlockBuffer?
        let length = avcc.count
        let allocated = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: length,
            blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
            offsetToData: 0, dataLength: length, flags: 0, blockBufferOut: &block)
        guard allocated == noErr, let block else { throw Failure.block(allocated) }
        let copyStatus = avcc.withUnsafeBytes { raw in
            CMBlockBufferReplaceDataBytes(with: raw.baseAddress!, blockBuffer: block,
                                          offsetIntoDestination: 0, dataLength: length)
        }
        guard copyStatus == noErr else { throw Failure.block(copyStatus) }
        let time = CMTime(value: Int64(presentationNanoseconds), timescale: 1_000_000_000)
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: time,
                                        decodeTimeStamp: .invalid)
        var sampleLength = length
        var sample: CMSampleBuffer?
        let status = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault, dataBuffer: block,
            formatDescription: format, sampleCount: 1,
            sampleTimingEntryCount: 1, sampleTimingArray: &timing,
            sampleSizeEntryCount: 1, sampleSizeArray: &sampleLength,
            sampleBufferOut: &sample)
        guard status == noErr, let sample else { throw Failure.sample(status) }
        return sample
    }
}
