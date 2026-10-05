//
//  LiveSpeechTranscriber.swift
//  VoiceCommand
//
//  SFSpeechRecognizer + AVAudioEngine behind `SpeechTranscribing`.
//

#if os(iOS)

import Foundation
import Speech
import AVFoundation

final class LiveSpeechTranscriber: SpeechTranscribing {
    private let engine = AVAudioEngine()
    private let recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    init(locale: Locale) {
        recognizer = SFSpeechRecognizer(locale: locale)
    }

    var isAvailable: Bool { recognizer?.isAvailable ?? false }

    func start(contextualStrings: [String], onEvent: @escaping @MainActor @Sendable (TranscriptEvent) -> Void) throws {
        guard let recognizer else { return }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.contextualStrings = contextualStrings
        self.request = request

        Self.installTap(on: engine, feeding: request)
        engine.prepare()
        try engine.start()

        task = Self.startRecognitionTask(recognizer, request, onEvent: onEvent)
    }

    func stop() {
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Speech and AVFoundation call back on their own queues. Under
    /// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` a closure written inline in
    /// this class would be inferred `@MainActor` and trap in
    /// `swift_task_checkIsolated` the moment the framework invoked it, so each
    /// one lives in a `nonisolated` function and hops to the main actor itself.
    nonisolated private static func installTap(
        on engine: AVAudioEngine,
        feeding request: SFSpeechAudioBufferRecognitionRequest
    ) {
        let input = engine.inputNode
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
            request.append(buffer)
        }
    }

    nonisolated private static func startRecognitionTask(
        _ recognizer: SFSpeechRecognizer,
        _ request: SFSpeechAudioBufferRecognitionRequest,
        onEvent: @escaping @MainActor @Sendable (TranscriptEvent) -> Void
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            let event: TranscriptEvent
            if let error = error.map({ $0 as NSError }) {
                if isNoSpeech(error) { return }
                event = .failure(error.localizedDescription)
            } else if let text = result?.bestTranscription.formattedString {
                event = .text(text, isFinal: result?.isFinal ?? false)
            } else {
                return
            }
            Task { @MainActor in onEvent(event) }
        }
    }

    /// "No speech detected" is routine silence, not a failure.
    nonisolated private static func isNoSpeech(_ e: NSError) -> Bool {
        (e.domain == "SFSpeechRecognizerErrorDomain" && e.code == 1)
            || (e.domain == "kAFAssistantErrorDomain" && (e.code == 1101 || e.code == 1110))
    }
}

nonisolated struct LiveSpeechAuthorizer: SpeechAuthorizing {
    func requestAuthorization() async -> VoiceAuthorization {
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        switch status {
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        @unknown default: return .unknown
        }
    }
}

#endif
