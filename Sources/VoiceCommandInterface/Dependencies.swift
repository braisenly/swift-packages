//
//  Dependencies.swift
//  VoiceCommand
//

import Foundation

public struct VoiceCommandDependencies {
    public var transcriber: any SpeechTranscribing
    public var authorizer: any SpeechAuthorizing
    public var clock: any Clock<Duration>

    public init(transcriber: any SpeechTranscribing, authorizer: any SpeechAuthorizing, clock: any Clock<Duration>) {
        self.transcriber = transcriber
        self.authorizer = authorizer
        self.clock = clock
    }
}
