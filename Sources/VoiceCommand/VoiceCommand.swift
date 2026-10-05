//
//  VoiceCommand.swift
//  VoiceCommand
//
//  Entry point. Hosts build a controller once, keep it alive while voice is
//  usable, and show its overlay; nothing else is needed from the host.
//

import SwiftUI
@_exported import VoiceCommandInterface
@_exported import VoiceCommandCore
@_exported import VoiceCommandLive
import VoiceCommandUI

public enum VoiceCommand {
    public static func makeController(
        configuration: VoiceCommandConfiguration = .init(),
        dependencies: VoiceCommandDependencies
    ) -> VoiceCommandController {
        VoiceCommandController(configuration: configuration, dependencies: dependencies)
    }

    #if os(iOS)
    public static func makeOverlay(_ controller: VoiceCommandController) -> some View {
        VoiceCommandOverlay(controller: controller)
    }
    #endif
}
