import AVFoundation
import Foundation

/// Minimal voice-note recorder (m4a, 16 kHz mono — exactly what the
/// transcribers like) with a live level meter for the waveform UI.
@MainActor
final class AudioRecorder: NSObject, ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var level: Double = 0
    @Published private(set) var elapsed: TimeInterval = 0
    @Published var errorMessage: String?

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var fileURL: URL?

    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
            }
        }
    }

    func start() async {
        guard !isRecording else { return }
        guard await requestPermission() else {
            errorMessage = "Microphone access is off. Enable it in Settings ▸ Kocharian AI."
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
            try session.setActive(true, options: [])

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("voice-\(Int(Date().timeIntervalSince1970)).m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.isMeteringEnabled = true
            recorder.record()

            self.recorder = recorder
            self.fileURL = url
            isRecording = true
            elapsed = 0
            startTimer()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Stops and returns the recorded file (`nil` if it was too short).
    @discardableResult
    func stop() -> URL? {
        guard let recorder else { return nil }
        recorder.stop()
        stopTimer()
        isRecording = false
        level = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        self.recorder = nil
        guard elapsed > 0.4 else {
            if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
            return nil
        }
        return fileURL
    }

    func cancel() {
        _ = stop()
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
        fileURL = nil
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let recorder = self.recorder else { return }
                recorder.updateMeters()
                let power = Double(recorder.averagePower(forChannel: 0))   // -160…0 dB
                let normalized = max(0, min(1, (power + 55) / 55))
                self.level = normalized
                self.elapsed = recorder.currentTime
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
