// SpeechRecognizer.swift

#if os(iOS)

import Foundation
import Speech
import AVFoundation
import Combine
import SwiftUI
import os.log
import Observation

@MainActor
@Observable
final class SpeechRecognizer {
    // MARK: - Published Properties
    var isListening: Bool = false
    var indicatorColor: Color = .red
    var furtherCommandsText: String = ""
    var isTriggerDetected: Bool = false
    var errorMessage: String? = nil
    var command: String? = nil
    var countdownRemaining: Int = 0

    // MARK: - Private Properties
    private var audioEngine = AVAudioEngine()
    private var speechRecognizerInstance: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    private var countdownTimer: DispatchSourceTimer?
    private let countdownDuration: TimeInterval = 6.0 // 6 seconds

    private let triggerWord = "genie"
    var allowedCommands = ["add ingredient", "remove ingredient"]

    private var newRecipeDetected = false
    private var lastNonEmptyRecognized: String? = nil

    // A dedicated queue for all speech recognition logic
    private let recognitionQueue = DispatchQueue(label: "com.braisenly.playground.speechRecognitionQueue", qos: .userInitiated)

    private let logger = Logger(subsystem: "com.braisenly.playground.SpeechRecognizer", category: "SpeechRecognizer")
    // MARK: - Initializer
    init() {
        let isPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        if isPreview {
            // For previews, no speech recognition
            isListening = false
            indicatorColor = .red
            isTriggerDetected = false
            furtherCommandsText = ""
            countdownRemaining = 0
            logger.log("Initialized in Preview mode.")
            return
        }

        setupSpeechRecognizer()
        logger.log("SpeechRecognizer initialized.")
    }

    deinit {
        Task { [weak self] in
            await self?.stopListening()
        }
        logger.log("SpeechRecognizer deinitialized.")
    }

    // MARK: - Setup Methods
    private func setupSpeechRecognizer() {
        speechRecognizerInstance = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        requestSpeechAuthorization()
    }

    private func requestSpeechAuthorization() {
        SFSpeechRecognizer.requestAuthorization { [weak self] authStatus in
            guard let self = self else { return }
            switch authStatus {
            case .authorized:
                self.logger.log("Speech recognition authorized.")
                Task {
                    await self.startListeningForTrigger()
                }
            case .denied:
                self.errorMessage = "Speech recognition authorization denied."
                self.logger.error("Speech recognition authorization denied.")
            case .restricted:
                self.errorMessage = "Speech recognition restricted on this device."
                self.logger.error("Speech recognition restricted on this device.")
            case .notDetermined:
                self.errorMessage = "Speech recognition not yet authorized."
                self.logger.error("Speech recognition not yet authorized.")
            @unknown default:
                self.errorMessage = "Unknown speech recognition authorization status."
                self.logger.error("Unknown speech recognition authorization status.")
            }
        }
    }

    // MARK: - Listening Methods
    private func startListeningForTrigger() async {
        resetStateForNewSession()

        guard let recognizer = speechRecognizerInstance, recognizer.isAvailable else {
            setError("Speech recognizer not available.")
            logger.error("Speech recognizer not available.")
            return
        }

        setupAudioSession()

        request = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = request else {
            setError("Unable to create recognition request for Tier-1.")
            logger.error("Unable to create recognition request for Tier-1.")
            return
        }

        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.contextualStrings = [triggerWord] + allowedCommands

        cancelCurrentTask()

        recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            Task { @MainActor in
                guard let self = self else { return }

                if let error = error {
                    if self.isNoSpeechError(error) {
                        // No speech - normal, keep waiting
                        return
                    } else {
                        self.handleRecognitionError(tier: "Tier-1", error: error)
                        await self.resetForNewSession()
                        return
                    }
                }

                if let result = result {
                    let spokenText = result.bestTranscription.formattedString
                        .lowercased()
                        .trimmingCharacters(in: .whitespacesAndNewlines)

                    self.logger.log("Tier-1 recognized: \(spokenText)")

                    if spokenText.contains(self.triggerWord) && !self.isTriggerDetected {
                        self.isTriggerDetected = true
                        self.updateIndicator(to: .green)
                        await self.stopListening()
                        Task {
                            await self.startListeningForCommands()
                        }
                    }
                }
            }
        }

        configureMicrophoneInput()
        startAudioEngine()
        logger.log("Tier-1 started - Listening for trigger word.")
    }

    private func startListeningForCommands() async {
        furtherCommandsText = ""
        newRecipeDetected = false
        lastNonEmptyRecognized = nil
        startCountdown()

        guard let recognizer = speechRecognizerInstance, recognizer.isAvailable else {
            setError("Speech recognizer not available for Tier-2.")
            logger.error("Speech recognizer not available for Tier-2.")
            return
        }

        setupAudioSession()

        request = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = request else {
            setError("Unable to create recognition request for Tier-2.")
            logger.error("Unable to create recognition request for Tier-2.")
            return
        }

        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.contextualStrings = allowedCommands

        cancelCurrentTask()

        recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            Task { @MainActor in
                guard let self = self else { return }

                if let error = error {
                    if self.isNoSpeechError(error) {
                        self.logger.debug("No speech in Tier-2; waiting for commands.")
                        return
                    } else {
                        self.handleRecognitionError(tier: "Tier-2", error: error)
                        self.stopListeningForCommands()
                        return
                    }
                }

                if let result = result {
                    let spokenText = result.bestTranscription.formattedString
                        .lowercased()
                        .trimmingCharacters(in: .whitespacesAndNewlines)

                    self.logger.log("Tier-2 recognized: \(spokenText)")

                    if spokenText.contains("new recipe") {
                        self.newRecipeDetected = true
                    }

                    if let matchedCommand = self.allowedCommands.first(where: { spokenText.contains($0) }) {
                        if matchedCommand == "new recipe" {
                            self.logger.log("Detected 'new recipe', waiting for name...")
                            self.lastNonEmptyRecognized = spokenText
                        } else {
                            // Normal command recognized immediately
                            self.furtherCommandsText = matchedCommand
                            self.command = matchedCommand
                            self.stopListeningForCommands()
                        }
                    } else {
                        // No direct match yet
                        if !spokenText.isEmpty {
                            self.lastNonEmptyRecognized = spokenText
                        }

                        if result.isFinal {
                            if self.newRecipeDetected {
                                self.handleFinalNewRecipe(spokenText: spokenText)
                            } else {
                                self.logger.log("Final result, no recognized commands.")
                                self.stopListeningForCommands()
                            }
                        } else {
                            self.logger.debug("Partial result, waiting for more speech...")
                        }
                    }
                }
            }
        }

        configureMicrophoneInput()
        startAudioEngine()
        logger.log("Tier-2 started - Listening for further commands.")
    }

    private func handleFinalNewRecipe(spokenText: String) {
        furtherCommandsText = spokenText
        command = "new recipe"
        stopListeningForCommands()
    }

    // MARK: - Audio Setup and Control
    private func setupAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
            try audioSession.setPreferredSampleRate(22050)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            logger.log("Audio session set up successfully.")
        } catch {
            setError("Audio session setup error: \(error.localizedDescription)")
            logger.error("Audio session setup error: \(error)")
        }
    }

    private func configureMicrophoneInput() {
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }
        logger.log("Microphone input configured.")
    }

    private func startAudioEngine() {
        do {
            audioEngine.prepare()
            try audioEngine.start()
            isListening = true
            logger.log("Audio engine started.")
        } catch {
            setError("Audio engine start error: \(error.localizedDescription)")
            logger.error("Audio engine start error: \(error)")
        }
    }

    private func stopListening() async {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionTask?.cancel()
        recognitionTask = nil
        request = nil
        isListening = false
        logger.log("Stopped listening.")
    }

    // MARK: - Countdown and Timeout
    private func startCountdown() {
        countdownTimer?.cancel()
        countdownRemaining = Int(countdownDuration)

        let timerQueue = DispatchQueue(label: "com.youbraisenly.playgroundrapp.speechQueue.timer")
        countdownTimer = DispatchSource.makeTimerSource(queue: timerQueue)
        countdownTimer?.schedule(deadline: .now(), repeating: 1.0)
        countdownTimer?.setEventHandler { [weak self] in
            guard let self = self else { return }
            if self.countdownRemaining > 0 {
                self.countdownRemaining -= 1
                self.logger.debug("Countdown: \(self.countdownRemaining)")
            } else {
                self.handleTimeout()
            }
        }
        countdownTimer?.resume()
        logger.log("Countdown started (6s) in Tier-2.")
    }

    private func handleTimeout() {
        logger.log("Countdown reached - Finalizing commands.")
        if newRecipeDetected {
            if let backupText = lastNonEmptyRecognized {
                handleFinalNewRecipe(spokenText: backupText)
            } else {
                furtherCommandsText = "new recipe"
                command = "new recipe"
                stopListeningForCommands()
            }
        } else {
            logger.log("No commands detected by timeout.")
            stopListeningForCommands()
        }
    }

    // MARK: - Reset Methods
    private func resetStateForNewSession() {
        newRecipeDetected = false
        lastNonEmptyRecognized = nil
        furtherCommandsText = ""
        command = nil
        errorMessage = nil
        isTriggerDetected = false
        logger.log("State reset for new session.")
    }

    private func resetForNewSession() async {
        await stopListening()
        resetStateForNewSession()
        Task {
            await startListeningForTrigger()
        }
        logger.log("Reset for new session.")
    }

    // MARK: - Error Handling
    private func handleRecognitionError(tier: String, error: Error) {
        errorMessage = "Recognition error in \(tier): \(error.localizedDescription)"
        logger.error("Critical error in \(tier): \(error.localizedDescription)")
    }

    private func isNoSpeechError(_ error: Error) -> Bool {
        let nsError = error as NSError
        logger.debug("Error Domain: \(nsError.domain), Code: \(nsError.code), Desc: \(nsError.localizedDescription)")

        // No speech conditions: code 1 or kAFAssistantErrorDomain code 1101/1110
        if nsError.domain == "SFSpeechRecognizerErrorDomain" && nsError.code == 1 {
            return true
        } else if nsError.domain == "kAFAssistantErrorDomain" && (nsError.code == 1101 || nsError.code == 1110) {
            return true
        }
        return false
    }

    private func updateIndicator(to color: Color) {
        indicatorColor = color
        logger.debug("Indicator color updated to \(color).")
    }

    private func setError(_ message: String) {
        errorMessage = message
        logger.error("Error set: \(message)")
    }

    // MARK: - Task Management

    private func cancelCurrentTask() {
        recognitionTask?.cancel()
        recognitionTask = nil
        request = nil
        logger.debug("Canceled current recognition task.")
    }

    private func stopListeningForCommands() {
        countdownTimer?.cancel()
        Task { [weak self] in
            await self?.stopListening()
        }
        logger.log("Stopped listening for commands.")
    }
}

#endif
