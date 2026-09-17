//
//  SpeechRecognizer.swift
//  playground
//
//  Two-tier voice command listener: wait for the trigger word, then open a
//  6 s command window and hand a parsed `SpeechCommand` to the UI.
//  Lifecycle is owner-driven: call `start()` on a user gesture and `stop()`
//  when the hosting view disappears. Everything runs on the main actor; the
//  Speech and audio callbacks hop back here with plain values only.
//

#if os(iOS)

import Foundation
import Speech
import AVFoundation
import Observation
import os

@MainActor
@Observable
final class SpeechRecognizer {
    enum Phase: Equatable { case idle, waitingForTrigger, listeningForCommands }

    private(set) var phase: Phase = .idle
    private(set) var transcript = ""
    private(set) var countdownRemaining = 0
    var errorMessage: String?
    /// Set once per recognized command. The consumer clears it after acting.
    var command: SpeechCommand?

    var isListening: Bool { phase != .idle }
    var interpreter = CommandInterpreter()

    private let commandWindowSeconds = 6
    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var countdown: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.braisenly.playground", category: "SpeechRecognizer")

    // MARK: - Public

    func setAvailableRecipes(_ recipes: [DBRecipe]) {
        interpreter.recipeNames = recipes.map { $0.name.lowercased() }
    }

    /// Speech, AVFoundation and TCC all call back on their own queues. Under
    /// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` a closure written inline here
    /// would be inferred `@MainActor` and trap in `swift_task_checkIsolated` the
    /// moment the framework invoked it, so each one lives in a `nonisolated`
    /// function and hops to the main actor itself.
    nonisolated private static func authorizationStatus() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
    }

    nonisolated private func installTap(
        on engine: AVAudioEngine,
        feeding request: SFSpeechAudioBufferRecognitionRequest
    ) {
        let input = engine.inputNode
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
            request.append(buffer)
        }
    }

    nonisolated private func startRecognitionTask(
        _ recognizer: SFSpeechRecognizer,
        _ request: SFSpeechAudioBufferRecognitionRequest
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let nsError = error.map { $0 as NSError }
            Task { @MainActor in
                self?.handle(text: text, isFinal: isFinal, error: nsError)
            }
        }
    }

    func start() async {
        guard phase == .idle else { return }
        errorMessage = nil
        let status = await Self.authorizationStatus()
        switch status {
        case .authorized: listen(.waitingForTrigger)
        case .denied: fail("Speech recognition denied in Settings.")
        case .restricted: fail("Speech recognition restricted on this device.")
        case .notDetermined: fail("Speech recognition not authorized.")
        @unknown default: fail("Unknown speech authorization status.")
        }
    }

    func stop() {
        tearDown()
        phase = .idle
        transcript = ""
    }

    // MARK: - Listening

    private func listen(_ next: Phase) {
        tearDown()
        guard let recognizer, recognizer.isAvailable else {
            fail("Speech recognizer not available."); return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.contextualStrings = interpreter.contextualStrings
            self.request = request

            installTap(on: engine, feeding: request)
            engine.prepare()
            try engine.start()

            task = startRecognitionTask(recognizer, request)
        } catch {
            fail("Audio setup failed: \(error.localizedDescription)"); return
        }

        phase = next
        transcript = ""
        if next == .listeningForCommands { startCountdown() }
        logger.log("Listening: \(String(describing: next))")
        dprint("[Speech] Listening: \(next)")
    }

    private func handle(text: String?, isFinal: Bool, error: NSError?) {
        guard phase != .idle else { return }
        if let error {
            if Self.isNoSpeech(error) { return }
            logger.error("Recognition error: \(error.localizedDescription)")
            dprint("[Speech] Recognition error: \(error.domain) \(error.code) \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            listen(.waitingForTrigger)
            return
        }
        guard let text else { return }
        transcript = text
        dprint("[Speech] \(phase) heard: \(text) final=\(isFinal)")

        switch phase {
        case .waitingForTrigger:
            if interpreter.containsTrigger(text) { listen(.listeningForCommands) }
        case .listeningForCommands:
            guard let cmd = interpreter.command(in: text) else {
                if isFinal { listen(.waitingForTrigger) }
                return
            }
            // "new recipe <name>" keeps collecting the name until the utterance ends.
            if case .newRecipe = cmd, !isFinal { return }
            deliver(cmd)
        case .idle:
            break
        }
    }

    private func deliver(_ cmd: SpeechCommand) {
        logger.log("Command: \(String(describing: cmd))")
        dprint("[Speech] Command: \(cmd)")
        command = cmd
        listen(.waitingForTrigger)
    }

    // MARK: - Command window

    private func startCountdown() {
        countdown?.cancel()
        countdown = Task { [weak self] in
            guard let self else { return }
            for remaining in stride(from: commandWindowSeconds, through: 1, by: -1) {
                countdownRemaining = remaining
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
            }
            countdownRemaining = 0
            if let cmd = interpreter.command(in: transcript) {
                deliver(cmd)
            } else {
                logger.log("Command window expired.")
                listen(.waitingForTrigger)
            }
        }
    }

    // MARK: - Teardown

    private func tearDown() {
        countdown?.cancel()
        countdown = nil
        countdownRemaining = 0
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func fail(_ message: String) {
        logger.error("\(message)")
        dprint("[Speech] Error: \(message)")
        errorMessage = message
        stop()
    }

    /// "No speech detected" is routine silence, not a failure.
    private static func isNoSpeech(_ e: NSError) -> Bool {
        (e.domain == "SFSpeechRecognizerErrorDomain" && e.code == 1)
            || (e.domain == "kAFAssistantErrorDomain" && (e.code == 1101 || e.code == 1110))
    }
}

#endif
