import AVFoundation
import Speech
import SwiftUI

/// Say "milk, two limes and a dozen eggs" and the words land in the quick-add field.
/// Uses the phone's own speech recognition where it can, so audio stays on the device.
@MainActor
@Observable
final class Dictation {
    var isListening = false
    var transcript = ""
    var message: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale.current)
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func toggle() async {
        if isListening { stop() } else { await start() }
    }

    func start() async {
        message = nil
        guard let recognizer, recognizer.isAvailable else {
            message = "Speech recognition isn't available right now."
            return
        }
        let speech = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) } }
        guard speech == .authorized else {
            message = "Allow Speech Recognition for Makin' Groceries in Settings to use dictation."
            return
        }
        let mic = await AVAudioApplication.requestRecordPermission()
        guard mic else {
            message = "Allow the microphone for Makin' Groceries in Settings to use dictation."
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
            self.request = request

            let input = engine.inputNode
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
                request.append(buffer)
            }
            engine.prepare()
            try engine.start()

            transcript = ""
            isListening = true
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let result { self.transcript = result.bestTranscription.formattedString }
                    if error != nil || result?.isFinal == true { self.stop() }
                }
            }
        } catch {
            message = "Couldn't start the microphone."
            stop()
        }
    }

    func stop() {
        guard isListening || engine.isRunning else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.finish()
        isListening = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
