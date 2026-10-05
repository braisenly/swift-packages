//
//  VoiceCommandOverlay.swift
//  VoiceCommand
//

#if os(iOS)

import SwiftUI
import VoiceCommandCore

package struct VoiceCommandOverlay: View {
    var controller: VoiceCommandController

    package init(controller: VoiceCommandController) {
        self.controller = controller
    }

    package var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if controller.isListening {
                HStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .symbolEffect(.variableColor.iterative, isActive: true)
                    Text(statusText)
                    if controller.phase == .listeningForCommands {
                        Text("\(controller.countdownRemaining)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.footnote)
                .padding(8)
                .glassIfAvailable(cornerRadius: 10)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            if let error = controller.errorMessage {
                HStack {
                    Text(error).font(.footnote).foregroundStyle(.red)
                    Button("Dismiss") { controller.errorMessage = nil }.font(.footnote)
                }
                .padding(8)
                .glassIfAvailable(cornerRadius: 10)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut, value: controller.phase)
        .animation(.easeInOut, value: controller.errorMessage)
    }

    private var statusText: String {
        switch controller.phase {
        case .idle: ""
        case .waitingForTrigger: "Say “genie”"
        case .listeningForCommands: controller.transcript.isEmpty ? "Listening…" : controller.transcript
        }
    }
}

#endif
