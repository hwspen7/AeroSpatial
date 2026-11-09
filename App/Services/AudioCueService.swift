import AVFoundation
import Foundation
import AeroSpatialCore

@MainActor
final class AudioCueService {
    private let speech = AVSpeechSynthesizer()
    private var lastAnnouncement: [String: TimeInterval] = [:]
    var enabled = false

    func announce(_ text: String, key: String, interval: TimeInterval = 30) {
        guard enabled else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if let previous = lastAnnouncement[key], now - previous < interval { return }
        lastAnnouncement[key] = now
        if speech.isSpeaking { speech.stopSpeaking(at: .immediate) }
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.49
        speech.speak(utterance)
    }

    func announcePosition(_ relative: RelativePosition) {
        let direction = DirectionCue.label(relativeBearing: relative.relativeBearingDegrees)
        let roundedDistance = Int((relative.distanceMeters / 10).rounded()) * 10
        announce("Drone \(direction.lowercased()), approximately \(roundedDistance) meters away.",
                 key: "position-\(direction)", interval: 45)
    }

    func silence() {
        speech.stopSpeaking(at: .immediate)
    }
}
