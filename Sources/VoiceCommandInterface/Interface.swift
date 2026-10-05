//
//  Interface.swift
//  VoiceCommand
//
//  Ports the voice command controller depends on. The live adapters wrap
//  Speech and AVFoundation; tests and previews use the scripted fakes.
//

import Foundation

/// One callback from the recognizer, already reduced to plain values.
/// "No speech detected" never arrives here: the live adapter drops it as routine silence.
public nonisolated enum TranscriptEvent: Equatable, Sendable {
    case text(String, isFinal: Bool)
    case failure(String)
}

public nonisolated enum VoiceAuthorization: Equatable, Sendable {
    case authorized, denied, restricted, notDetermined, unknown
}

/// Streams transcripts from the microphone. One session at a time: `start`
/// begins a fresh session, `stop` ends it and releases the audio session.
@MainActor
public protocol SpeechTranscribing: AnyObject {
    var isAvailable: Bool { get }
    func start(contextualStrings: [String], onEvent: @escaping @MainActor @Sendable (TranscriptEvent) -> Void) throws
    func stop()
}

public nonisolated protocol SpeechAuthorizing: Sendable {
    func requestAuthorization() async -> VoiceAuthorization
}
