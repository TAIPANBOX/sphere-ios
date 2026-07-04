#if os(iOS)
import Foundation
import Speech
import AVFoundation
import Observation

/// Live speech-to-text for the chat input. Prefers on-device recognition
/// (private, offline) where the locale supports it. Delivers partial
/// transcripts to `onText` as the user speaks.
@MainActor
@Observable
public final class SpeechDictation {
    public private(set) var isRecording = false

    private let recognizer = SFSpeechRecognizer(locale: Locale.current)
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var onText: ((String) -> Void)?

    public init() {}

    public var isAvailable: Bool {
        recognizer?.isAvailable ?? false
    }

    public func toggle(onText: @escaping (String) -> Void) {
        if isRecording {
            stop()
        } else {
            Task { await start(onText: onText) }
        }
    }

    private func start(onText: @escaping (String) -> Void) async {
        guard await authorize(), let recognizer, recognizer.isAvailable else { return }
        self.onText = onText

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try? session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request

        let input = audioEngine.inputNode
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
            request.append(buffer)
        }
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            stop()
            return
        }
        isRecording = true

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            // Background queue — only schedule main-actor work.
            guard let self else { return }
            if let text = result?.bestTranscription.formattedString {
                Task { @MainActor in self.deliver(text) }
            }
            if error != nil || (result?.isFinal ?? false) {
                Task { @MainActor in self.stop() }
            }
        }
    }

    private func deliver(_ text: String) {
        onText?(text)
    }

    public func stop() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        onText = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func authorize() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speech == .authorized else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }
}
#endif
