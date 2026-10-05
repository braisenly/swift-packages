//
//  ScriptedTranscriber.swift
//  VoiceCommand
//
//  Fakes for every port: drive the controller from tests, previews and the
//  example host without a microphone.
//

import Foundation
import VoiceCommandInterface

public final class ScriptedTranscriber: SpeechTranscribing {
    public var isAvailable = true
    /// Thrown by the next `start`, to simulate audio setup failure.
    public var startError: (any Error)?
    public private(set) var startCount = 0
    public private(set) var stopCount = 0
    public private(set) var lastContextualStrings: [String] = []
    private var onEvent: (@MainActor @Sendable (TranscriptEvent) -> Void)?

    public init() {}

    public var isRunning: Bool { onEvent != nil }

    public func start(contextualStrings: [String], onEvent: @escaping @MainActor @Sendable (TranscriptEvent) -> Void) throws {
        if let startError { throw startError }
        startCount += 1
        lastContextualStrings = contextualStrings
        self.onEvent = onEvent
    }

    public func stop() {
        stopCount += 1
        onEvent = nil
    }

    /// Deliver one recognizer callback to the current session.
    public func send(_ event: TranscriptEvent) {
        onEvent?(event)
    }
}

public nonisolated struct StubAuthorizer: SpeechAuthorizing {
    public var result: VoiceAuthorization

    public init(result: VoiceAuthorization = .authorized) {
        self.result = result
    }

    public func requestAuthorization() async -> VoiceAuthorization { result }
}

/// A clock whose sleeps return at once (after a yield), so the command window
/// expires immediately in tests and previews.
public nonisolated struct ImmediateClock: Clock {
    public struct Instant: InstantProtocol {
        public var offset: Duration = .zero
        public func advanced(by duration: Duration) -> Instant { Instant(offset: offset + duration) }
        public func duration(to other: Instant) -> Duration { other.offset - offset }
        public static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.offset < rhs.offset }
    }

    public var now = Instant()
    public var minimumResolution: Duration { .zero }

    public init() {}

    public func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        try Task.checkCancellation()
        await Task.yield()
    }
}

extension VoiceCommandDependencies {
    public static func scripted(
        transcriber: ScriptedTranscriber = ScriptedTranscriber(),
        authorization: VoiceAuthorization = .authorized,
        clock: any Clock<Duration> = ImmediateClock()
    ) -> Self {
        Self(transcriber: transcriber, authorizer: StubAuthorizer(result: authorization), clock: clock)
    }
}
