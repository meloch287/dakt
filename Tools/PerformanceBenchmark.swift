import AppKit
import SwiftUI
import Combine
import AVFoundation

/// Synthetic workloads only: no capture, credentials, user defaults or API requests.
/// Compiled by performance-check.sh against the same sources as the application.
@main
struct PerformanceBenchmark {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Task { @MainActor in
            do { try await run(); exit(0) }
            catch { print("Performance check failed: \(error)"); exit(1) }
        }
        app.run()
    }

    @MainActor private static func run() async throws {
        let calls = Counter()
        let stream = RecordedSpeechStream(locale: "ru-RU", prepare: { _ in }, transcribe: { _, _ in "" },
            now: { calls.increment(); return ProcessInfo.processInfo.systemUptime },
            onDraft: { _ in }, onUtterance: { _ in }, onError: { print($0) })
        try await stream.start()
        var start = Metrics()
        try await Task.sleep(nanoseconds: 2_000_000_000)
        report("silence_without_buffers", start: start, extra: ["clock_checks": calls.value])
        stream.stop()

        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        let audio = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 480)!
        audio.frameLength = 480
        for channel in 0..<2 {
            for index in 0..<480 { audio.floatChannelData![channel][index] = Float(index % 97) / 100 }
        }
        start = Metrics()
        var checksum: Float = 0
        for _ in 0..<200_000 { checksum += audio.peakLevel }
        report("pcm_peak_200000_buffers", start: start, extra: ["checksum": checksum])

        let preferences = AssistantPreferences(preview: true)
        let assistant = AssistantController(preferences: preferences, preview: true)
        assistant.loadExample()
        let engine = AnswerEngine { _, _, _, partial in
            var text = ""
            for index in 0..<600 {
                text += index % 12 == 0 ? "\n" : "текст "
                partial(text)
                try await Task.sleep(nanoseconds: 5_000_000)
            }
            return text + "Конец."
        }
        let window = AssistantWindow()
        window.setContentSize(NSSize(width: 1100, height: 720))
        let interaction = WindowInteractionLock(window: window) { preferences.windowLocked = false }
        var reports = 0
        window.contentView = NSHostingView(rootView: AssistantView(
            assistant: assistant, answers: engine, preferences: preferences,
            onSettings: {}, onHide: {},
            onLockControlChange: { reports += 1; interaction.updateControlView($0) },
            onHideControlChange: { reports += 1; interaction.updateHideControlView($0) }, isPreview: true))
        window.orderFrontRegardless()
        defer { interaction.setLocked(false); window.close() }
        try await Task.sleep(nanoseconds: 300_000_000)
        var publications = 0
        let observation = engine.$reply.dropFirst().sink { _ in publications += 1 }
        reports = 0
        start = Metrics()
        engine.ask("Синтетический поток из 600 фрагментов", recent: [], config: LunaConfiguration())
        while engine.reply?.isStreaming == true {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        guard engine.reply?.text.hasSuffix("Конец.") == true else { throw RecorderError.message("Lost final text") }
        report("stream_600_fragments", start: start,
               extra: ["reply_publications": publications, "anchor_reports": reports])
        withExtendedLifetime(observation) {}

        preferences.windowLocked = true
        interaction.setLocked(true)
        try await Task.sleep(nanoseconds: 200_000_000)
        reports = 0
        start = Metrics()
        try await Task.sleep(nanoseconds: 2_000_000_000)
        report("locked_static", start: start, extra: ["anchor_reports": reports])
        interaction.setLocked(false)
        preferences.windowLocked = false

        // Same changing background for the blur A/B experiment. WindowServer
        // is shared with other apps: its numbers are only supporting evidence.
        let backdrop = NSWindow(contentRect: window.frame.insetBy(dx: -30, dy: -30),
                                styleMask: [.borderless], backing: .buffered, defer: false)
        backdrop.isReleasedWhenClosed = false
        let motion = MovingBackground(frame: NSRect(origin: .zero, size: backdrop.frame.size))
        backdrop.contentView = motion
        backdrop.order(.below, relativeTo: window.windowNumber)
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { _ in
            MainActor.assumeIsolated { motion.step += 1; motion.needsDisplay = true }
        }
        defer { timer.invalidate(); backdrop.close() }
        for hideBlur in [false, true, false, true] {
            setBlurHidden(hideBlur, in: window.contentView!)
            try await Task.sleep(nanoseconds: 1_000_000_000)
            start = Metrics()
            try await Task.sleep(nanoseconds: 4_000_000_000)
            report(hideBlur ? "moving_background_blur_off" : "moving_background_default", start: start)
        }
    }

    @MainActor private static func setBlurHidden(_ hidden: Bool, in view: NSView) {
        if view is NSVisualEffectView { view.isHidden = hidden }
        for child in view.subviews { setBlurHidden(hidden, in: child) }
    }

    private static func report(_ scenario: String, start: Metrics, extra: [String: Any] = [:]) {
        let end = Metrics()
        let wall = end.wall - start.wall
        var values = extra
        values["scenario"] = scenario
        values["wall_seconds"] = wall
        values["cpu_seconds"] = end.cpu - start.cpu
        values["cpu_percent_one_core"] = 100 * (end.cpu - start.cpu) / wall
        values["peak_rss_mb"] = Double(end.usage.ru_maxrss) / 1_048_576
        if let before = start.windowServer, let after = end.windowServer {
            values["window_server_cpu_percent"] = 100 * (after - before) / wall
        }
        let data = try! JSONSerialization.data(withJSONObject: values, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
        fflush(stdout)
    }
}

private struct Metrics {
    let wall = ProcessInfo.processInfo.systemUptime
    var usage = rusage()
    let windowServer = windowServerCPU()
    var cpu: Double {
        Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
    }
    init() { getrusage(RUSAGE_SELF, &usage) }
}

private func windowServerCPU() -> Double? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/ps")
    process.arguments = ["-axo", "time=,comm="]
    let output = Pipe()
    process.standardOutput = output
    do { try process.run() } catch { return nil }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let rows = String(decoding: data, as: UTF8.self).split(separator: "\n")
    guard let row = rows.first(where: { $0.hasSuffix("/WindowServer") }),
          let value = row.split(separator: " ").first else { return nil }
    let parts = value.split(separator: ":").compactMap { Double($0) }
    return parts.count == 2 ? parts[0] * 60 + parts[1] : nil
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.withLock { count += 1 } }
    var value: Int { lock.withLock { count } }
}

@MainActor private final class MovingBackground: NSView {
    var step = 0
    override func draw(_ dirtyRect: NSRect) {
        for index in 0..<40 {
            NSColor(calibratedHue: CGFloat((index + step) % 120) / 120, saturation: 0.5, brightness: 0.75, alpha: 1).setFill()
            NSRect(x: 0, y: CGFloat(index) * bounds.height / 40, width: bounds.width, height: bounds.height / 40 + 1).fill()
        }
    }
}
