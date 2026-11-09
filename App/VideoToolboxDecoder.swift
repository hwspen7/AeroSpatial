import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox

/// Hardware-assisted decoder for fully formed CoreMedia video samples.
/// Encoded DJI NAL packets require a separate, verified sample-buffer adapter.
final class VideoToolboxDecoder {
    enum Failure: Error { case formatMissing, unsupportedFormat, setup(OSStatus), decode(OSStatus) }
    private var session: VTDecompressionSession?
    private var format: CMFormatDescription?

    /// Must be called serially on a video worker, never from UI or flight-control callbacks.
    func decode(_ sample: CMSampleBuffer,
                onFrame: @escaping (CVPixelBuffer, CMTime) -> Void) throws {
        guard let description = CMSampleBufferGetFormatDescription(sample) else {
            throw Failure.formatMissing
        }
        let dimensions = CMVideoFormatDescriptionGetDimensions(description)
        guard dimensions.width > 0, dimensions.height > 0,
              dimensions.width <= 8192, dimensions.height <= 8192 else {
            throw Failure.unsupportedFormat
        }
        if let active = session,
           !VTDecompressionSessionCanAcceptFormatDescription(active, formatDescription: description) {
            VTDecompressionSessionInvalidate(active)
            session = nil
            format = nil
        }
        if session == nil {
            let attributes: [CFString: Any] = [
                kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                kCVPixelBufferIOSurfacePropertiesKey: [:]
            ]
            var created: VTDecompressionSession?
            let status = VTDecompressionSessionCreate(allocator: kCFAllocatorDefault,
                         formatDescription: description, decoderSpecification: nil,
                         imageBufferAttributes: attributes as CFDictionary,
                         outputCallback: nil, decompressionSessionOut: &created)
            guard status == noErr, let created else { throw Failure.setup(status) }
            session = created
            format = description
        }
        guard let active = session else { throw Failure.formatMissing }
        var information = VTDecodeInfoFlags()
        let status = VTDecompressionSessionDecodeFrame(active, sampleBuffer: sample,
                            flags: [], infoFlagsOut: &information) {
            callbackStatus, _, imageBuffer, presentationTime, _ in
            guard callbackStatus == noErr, let imageBuffer else { return }
            onFrame(imageBuffer, presentationTime)
        }
        guard status == noErr else { throw Failure.decode(status) }
    }

    func shutdown() {
        if let session {
            _ = VTDecompressionSessionWaitForAsynchronousFrames(session)
            VTDecompressionSessionInvalidate(session)
        }
        session = nil
        format = nil
    }
    deinit { shutdown() }
}
