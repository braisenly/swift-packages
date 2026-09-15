// SpeechRecognizerOverlay.swift

#if os(iOS)

import SwiftUI

struct SpeechRecognizerOverlay: View {
    var speechRecognizer: SpeechRecognizer

    var body: some View {
        VStack {
            if speechRecognizer.isListening {
                HStack {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                        .transition(.scale)
                    
                    Text("Listening...")
                        .foregroundColor(.white)
                        .padding(.leading, 8)
                        .transition(.opacity)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.black.opacity(0.7))
                        .shadow(radius: 5)
                        .animation(.easeInOut, value: speechRecognizer.isListening)
                )
                .padding()
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.easeInOut, value: speechRecognizer.isListening)
            }
            
            if let error = speechRecognizer.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.black.opacity(0.7))
                            .shadow(radius: 5)
                    )
                    .padding()
                    .transition(.slide)
                    .animation(.easeInOut, value: speechRecognizer.errorMessage)
            }
        }
        .animation(.default, value: speechRecognizer.isListening)
    }
}

struct SpeechRecognizerOverlay_Previews: PreviewProvider {
    static var previews: some View {
        SpeechRecognizerOverlay(speechRecognizer: SpeechRecognizer())
            .previewLayout(.sizeThatFits)
    }
}

#endif
