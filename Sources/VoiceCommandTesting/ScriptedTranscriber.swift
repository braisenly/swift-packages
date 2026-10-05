//
//  ScriptedTranscriber.swift
//  VoiceCommand
//
//  Fakes for every port: drive the controller from tests, previews and the
//  example host without a microphone.
//

import Foundation

final class ScriptedTranscriber: SpeechTranscribing {
    var isAvailable = true
    /// Thrown by the next `start`, to simulate audio setup failure.
    var startError: (any Error)?
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var lastContextualStrings: [String] = []
    private var onEvent: (@MainActor @Sendable (TranscriptEvent) -> Void)?

    init() {}

    var isRunning: Bool { onEvent != nil }

    func start(contextualStrings: [String], onEvent: @escaping @MainActor @Sendable (TranscriptEvent) -> Void) throws {
        if let startError { throw startError }
        startCount += 1
        lastContextualStrings = contextualStrings
        self.onEvent = onEvent
    }

    func stop() {
        stopCount += 1
        onEvent = nil
    }

    /// Deliver one recognizer callback to the current session.
    func send(_ event: TranscriptEvent) {
        onEvent?(event)
    }
}

nonisolated struct StubAuthorizer: SpeechAuthorizing {
    var result: VoiceAuthorization = .authorized

    func requestAuthorization() async -> VoiceAuthorization { result }
}

/// A clock whose sleeps return at once (after a yield), so the command window
/// expires immediately in tests and previews.
nonisolated struct ImmediateClock: Clock {
    struct Instant: InstantProtocol {
        var offset: Duration = .zero
        func advanced(by duration: Duration) -> Instant { Instant(offset: offset + duration) }
        func duration(to other: Instant) -> Duration { other.offset - offset }
        static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.offset < rhs.offset }
    }

    var now = Instant()
    var minimumResolution: Duration { .zero }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        try Task.checkCancellation()
        await Task.yield()
    }
}

extension VoiceCommandDependencies {
    static func scripted(
        transcriber: ScriptedTranscriber = ScriptedTranscriber(),
        authorization: VoiceAuthorization = .authorized,
        clock: any Clock<Duration> = ImmediateClock()
    ) -> Self {
        Self(transcriber: transcriber, authorizer: StubAuthorizer(result: authorization), clock: clock)
    }
}
