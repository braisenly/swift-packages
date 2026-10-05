//
//  VoiceCommand.swift
//  VoiceCommand
//
//  Entry point. Hosts build a controller once, keep it alive while voice is
//  usable, and show its overlay; nothing else is needed from the host.
//

import SwiftUI

enum VoiceCommand {
    static func makeController(
        configuration: VoiceCommandConfiguration = .init(),
        dependencies: VoiceCommandDependencies
    ) -> VoiceCommandController {
        VoiceCommandController(configuration: configuration, dependencies: dependencies)
    }

    #if os(iOS)
    static func makeOverlay(_ controller: VoiceCommandController) -> some View {
        VoiceCommandOverlay(controller: controller)
    }
    #endif
}
