import Foundation

/// A synchronized metadata snapshot, not a decoded image or georeferenced target.
public struct FrameBundle: Equatable, Sendable {
    public let video: TimelinePoint
    public let head: TimelinePoint
    public let telemetry: TimelinePoint
    public let referenceNanoseconds: UInt64
    public let maximumSkewNanoseconds: UInt64

    /// The timeline must already contain explicit normalized timestamps and uncertainties.
    public static func resolve(in timeline: MultimodalTimeline,
                               at referenceNanoseconds: UInt64,
                               maximumSkewNanoseconds: UInt64,
                               maximumClockUncertaintyNanoseconds: UInt64) -> FrameBundle? {
        guard let alignment = timeline.aligned(
            at: referenceNanoseconds, requiring: [.video, .head, .telemetry],
            maximumSkewNanoseconds: maximumSkewNanoseconds,
            maximumClockUncertaintyNanoseconds: maximumClockUncertaintyNanoseconds),
            let video = alignment.observations[.video],
            let head = alignment.observations[.head],
            let telemetry = alignment.observations[.telemetry] else { return nil }
        return FrameBundle(video: video, head: head, telemetry: telemetry,
                           referenceNanoseconds: referenceNanoseconds,
                           maximumSkewNanoseconds: alignment.maximumObservedSkewNanoseconds)
    }
}
