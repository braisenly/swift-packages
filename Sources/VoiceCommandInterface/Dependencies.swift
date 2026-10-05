//
//  Dependencies.swift
//  VoiceCommand
//

import Foundation

struct VoiceCommandDependencies {
    var transcriber: any SpeechTranscribing
    var authorizer: any SpeechAuthorizing
    var clock: any Clock<Duration>
}

#if os(iOS)
extension VoiceCommandDependencies {
    /// Microphone + on-device Speech recognition.
    static func live(locale: Locale = Locale(identifier: "en-US")) -> Self {
        Self(
            transcriber: LiveSpeechTranscriber(locale: locale),
            authorizer: LiveSpeechAuthorizer(),
            clock: ContinuousClock()
        )
    }
}
#endif
