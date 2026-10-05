//
//  Configuration.swift
//  VoiceCommand
//

import Foundation

nonisolated struct VoiceCommandConfiguration: Sendable {
    /// Seconds the command window stays open after the trigger word.
    var commandWindowSeconds = 6
    /// Restart the trigger session once its transcript passes this, so a long
    /// conversation near the device cannot drown the wake word.
    var maxIdleTranscriptLength = 120
    /// `os.Logger` subsystem; hosts pass their own bundle-style identifier.
    var logSubsystem = "com.braisenly.VoiceCommand"
}
