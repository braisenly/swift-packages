// SpeechRecognizerOverlay.swift

#if os(iOS)

import SwiftUI

struct SpeechRecognizerOverlay: View {
    var speech: SpeechRecognizer

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if speech.isListening {
                HStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .symbolEffect(.variableColor.iterative, isActive: true)
                    Text(statusText)
                    if speech.phase == .listeningForCommands {
                        Text("\(speech.countdownRemaining)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.footnote)
                .padding(8)
                .glassIfAvailable(cornerRadius: 10)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            if let error = speech.errorMessage {
                HStack {
                    Text(error).font(.footnote).foregroundStyle(.red)
                    Button("Dismiss") { speech.errorMessage = nil }.font(.footnote)
                }
                .padding(8)
                .glassIfAvailable(cornerRadius: 10)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut, value: speech.phase)
        .animation(.easeInOut, value: speech.errorMessage)
    }

    private var statusText: String {
        switch speech.phase {
        case .idle: ""
        case .waitingForTrigger: "Say “genie”"
        case .listeningForCommands: speech.transcript.isEmpty ? "Listening…" : speech.transcript
        }
    }
}

#Preview {
    SpeechRecognizerOverlay(speech: SpeechRecognizer())
}

#endif
