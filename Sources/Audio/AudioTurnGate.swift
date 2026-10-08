import Foundation

struct AudioTurnGate {
    struct Boundary: Equatable {
        let shouldTranscribe: Bool
        let endsTurn: Bool
    }

    let silence: TimeInterval
    static let maximumClipDuration: TimeInterval = 12
    private var opened: TimeInterval?
    private var lastVoice: TimeInterval?
    private var voiceDuration: TimeInterval = 0
    private var hasUsefulSegment = false
    var isRecording: Bool { opened != nil }
    var hasOpenTurn: Bool { lastVoice != nil }

    init(silence: TimeInterval = SpeechTiming.defaultPause) {
        self.silence = SpeechTiming.normalized(silence)
    }

    /// true только на первом звуковом буфере нового аудиофайла.
    mutating func append(level: Float, duration: TimeInterval, at now: TimeInterval) -> Bool {
        guard level >= 0.01 else { return false }
        let started = opened == nil
        if started { opened = now - duration }
        lastVoice = now
        voiceDuration += duration
        return started
    }

    /// Техническая граница файла не завершает вопрос. После неё сохраняем
    /// время последней речи, чтобы отправить финальную границу даже без нового файла.
    mutating func finishIfDue(at now: TimeInterval) -> Boundary? {
        guard let lastVoice else { return nil }
        let endsTurn = now - lastVoice >= silence
        let clipIsFull = opened.map { now - $0 >= Self.maximumClipDuration } ?? false
        guard endsTurn || clipIsFull else { return nil }
        let useful = voiceDuration >= 0.12 || (hasUsefulSegment && voiceDuration > 0)
        opened = nil
        voiceDuration = 0
        if endsTurn {
            self.lastVoice = nil
            hasUsefulSegment = false
        } else {
            hasUsefulSegment = hasUsefulSegment || useful
        }
        return Boundary(shouldTranscribe: useful, endsTurn: endsTurn)
    }
}
