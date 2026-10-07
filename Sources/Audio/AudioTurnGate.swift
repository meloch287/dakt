import Foundation

struct AudioTurnGate {
    static let silence: TimeInterval = 0.4
    private var opened: TimeInterval?
    private var lastVoice: TimeInterval = 0
    private var voiceDuration: TimeInterval = 0
    var isRecording: Bool { opened != nil }

    /// true только на первом звуковом буфере новой фразы.
    mutating func append(level: Float, duration: TimeInterval, at now: TimeInterval) -> Bool {
        guard level >= 0.01 else { return false }
        let started = opened == nil
        if started { opened = now - duration }
        lastVoice = now
        voiceDuration += duration
        return started
    }

    /// nil — ещё записываем; false — щелчок, который нужно отбросить.
    mutating func finishIfDue(at now: TimeInterval) -> Bool? {
        guard let opened,
              now - lastVoice >= Self.silence || now - opened >= 12 else { return nil }
        let useful = voiceDuration >= 0.12
        self = AudioTurnGate()
        return useful
    }
}
