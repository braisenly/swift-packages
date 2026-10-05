//
//  VoiceCommandController.swift
//  VoiceCommand
//
//  Two-tier voice command listener: wait for the trigger word, then open a
//  command window and hand a parsed `SpeechCommand` to the UI.
//  Lifecycle is owner-driven: call `start()` on a user gesture and `stop()`
//  when the hosting view disappears. Everything runs on the main actor; the
//  transcriber delivers plain values back here.
//

import Foundation
import Observation
import os
import VoiceCommandInterface

@MainActor
@Observable
public final class VoiceCommandController {
    public enum Phase: Equatable { case idle, waitingForTrigger, listeningForCommands }

    public private(set) var phase: Phase = .idle
    public private(set) var transcript = ""
    public private(set) var countdownRemaining = 0
    public var errorMessage: String?
    /// Set once per recognized command. The consumer clears it after acting.
    public var command: SpeechCommand?

    public var isListening: Bool { phase != .idle }
    public var interpreter = CommandInterpreter()

    private let configuration: VoiceCommandConfiguration
    private let transcriber: any SpeechTranscribing
    private let authorizer: any SpeechAuthorizing
    private let clock: any Clock<Duration>
    private var countdown: Task<Void, Never>?
    private let logger: Logger

    public init(configuration: VoiceCommandConfiguration, dependencies: VoiceCommandDependencies) {
        self.configuration = configuration
        transcriber = dependencies.transcriber
        authorizer = dependencies.authorizer
        clock = dependencies.clock
        logger = Logger(subsystem: configuration.logSubsystem, category: "VoiceCommand")
    }

    // MARK: - Public

    /// Recipe names the user can `open`; matched case-insensitively.
    public func setVocabulary(recipeNames: [String]) {
        interpreter.recipeNames = recipeNames.map { $0.lowercased() }
    }

    public func start() async {
        guard phase == .idle else { return }
        errorMessage = nil
        switch await authorizer.requestAuthorization() {
        case .authorized: listen(.waitingForTrigger)
        case .denied: fail("Speech recognition denied in Settings.")
        case .restricted: fail("Speech recognition restricted on this device.")
        case .notDetermined: fail("Speech recognition not authorized.")
        case .unknown: fail("Unknown speech authorization status.")
        }
    }

    public func stop() {
        tearDown()
        phase = .idle
        transcript = ""
    }

    // MARK: - Listening

    private func listen(_ next: Phase) {
        tearDown()
        guard transcriber.isAvailable else {
            fail("Speech recognizer not available."); return
        }
        do {
            try transcriber.start(contextualStrings: interpreter.contextualStrings) { [weak self] event in
                self?.handle(event)
            }
        } catch {
            fail("Audio setup failed: \(error.localizedDescription)"); return
        }

        phase = next
        transcript = ""
        if next == .listeningForCommands { startCountdown() }
        logger.log("Listening: \(String(describing: next))")
    }

    private func handle(_ event: TranscriptEvent) {
        guard phase != .idle else { return }
        let text: String
        let isFinal: Bool
        switch event {
        case .failure(let message):
            logger.error("Recognition error: \(message)")
            errorMessage = message
            listen(.waitingForTrigger)
            return
        case .text(let heard, let final):
            text = heard
            isFinal = final
        }
        transcript = text

        switch phase {
        case .waitingForTrigger:
            if interpreter.containsTrigger(text) {
                listen(.listeningForCommands)
            } else if isFinal || text.count > configuration.maxIdleTranscriptLength {
                // Speech keeps one utterance open indefinitely. Left alone, the
                // trigger phase accumulates every word spoken near the device and
                // the recogniser's accuracy collapses; restart with a clean buffer.
                listen(.waitingForTrigger)
            }
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
        command = cmd
        listen(.waitingForTrigger)
    }

    // MARK: - Command window

    private func startCountdown() {
        countdown?.cancel()
        countdown = Task { [weak self, clock] in
            guard let self else { return }
            for remaining in stride(from: configuration.commandWindowSeconds, through: 1, by: -1) {
                countdownRemaining = remaining
                try? await clock.sleep(for: .seconds(1))
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
        transcriber.stop()
    }

    private func fail(_ message: String) {
        logger.error("\(message)")
        errorMessage = message
        stop()
    }
}
