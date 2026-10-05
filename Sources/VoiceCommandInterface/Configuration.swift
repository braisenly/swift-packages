//
//  Configuration.swift
//  VoiceCommand
//

import Foundation

public nonisolated struct VoiceCommandConfiguration: Sendable {
    /// Seconds the command window stays open after the trigger word.
    public var commandWindowSeconds: Int
    /// Restart the trigger session once its transcript passes this, so a long
    /// conversation near the device cannot drown the wake word.
    public var maxIdleTranscriptLength: Int
    /// `os.Logger` subsystem; hosts pass their own bundle-style identifier.
    public var logSubsystem: String

    public init(
        commandWindowSeconds: Int = 6,
        maxIdleTranscriptLength: Int = 120,
        logSubsystem: String = "com.braisenly.VoiceCommand"
    ) {
        self.commandWindowSeconds = commandWindowSeconds
        self.maxIdleTranscriptLength = maxIdleTranscriptLength
        self.logSubsystem = logSubsystem
    }
}
