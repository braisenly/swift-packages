//
//  VoiceCommandExampleApp.swift
//  VoiceCommandExample
//
//  Drop-in proof for the VoiceCommand capability: one package dependency,
//  one entry point. Demo mode drives the controller with a scripted
//  transcriber; Microphone mode uses the live Speech adapter.
//

import SwiftUI
import VoiceCommand
import VoiceCommandTesting

@main
struct VoiceCommandExampleApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

struct ContentView: View {
    enum Mode: String, CaseIterable { case demo = "Demo", live = "Microphone" }
    @State private var mode = Mode.demo

    var body: some View {
        NavigationStack {
            Group {
                switch mode {
                case .demo: DemoView()
                case .live: LiveView()
                }
            }
            .navigationTitle("VoiceCommand")
            .toolbar {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
            }
        }
    }
}

private let recipes = ["Pancakes", "Waffles"]

/// Scripted phrases stand in for speech; each tap is one final utterance.
struct DemoView: View {
    @State private var transcriber: ScriptedTranscriber
    @State private var voice: VoiceCommandController
    @State private var received: [String] = []

    init() {
        let transcriber = ScriptedTranscriber()
        let voice = VoiceCommand.makeController(dependencies: .scripted(transcriber: transcriber, clock: ContinuousClock()))
        voice.setVocabulary(recipeNames: recipes)
        _transcriber = State(initialValue: transcriber)
        _voice = State(initialValue: voice)
    }

    var body: some View {
        List {
            Section("Say") {
                ForEach(["genie", "open pancakes", "new recipe waffles", "add ingredient"], id: \.self) { phrase in
                    Button(phrase) { transcriber.send(.text(phrase, isFinal: true)) }
                        .accessibilityIdentifier("say-\(phrase)")
                }
            }
            CommandLog(received: received)
        }
        .overlay(alignment: .topTrailing) { VoiceCommand.makeOverlay(voice).padding() }
        .task {
            await voice.start()
            // `-autoDemo` plays the phrases unattended (CI / screenshot evidence).
            guard CommandLine.arguments.contains("-autoDemo") else { return }
            for phrase in ["genie", "open pancakes", "genie", "new recipe waffles", "genie"] {
                try? await Task.sleep(for: .milliseconds(400))
                transcriber.send(.text(phrase, isFinal: true))
            }
        }
        .onChange(of: voice.command) { _, command in
            guard let command else { return }
            voice.command = nil
            received.insert(String(describing: command), at: 0)
        }
    }
}

struct LiveView: View {
    @State private var voice = VoiceCommand.makeController(dependencies: .live())
    @State private var received: [String] = []

    var body: some View {
        List {
            Section {
                Button(voice.isListening ? "Stop listening" : "Start listening") {
                    if voice.isListening { voice.stop() } else { Task { await voice.start() } }
                }
                .accessibilityIdentifier("VoiceToggle")
                Text("Say “genie”, then “open pancakes” or “new recipe waffles”.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            CommandLog(received: received)
        }
        .overlay(alignment: .topTrailing) { VoiceCommand.makeOverlay(voice).padding() }
        .onAppear { voice.setVocabulary(recipeNames: recipes) }
        .onDisappear { voice.stop() }
        .onChange(of: voice.command) { _, command in
            guard let command else { return }
            voice.command = nil
            received.insert(String(describing: command), at: 0)
        }
    }
}

struct CommandLog: View {
    let received: [String]

    var body: some View {
        Section("Commands received") {
            if received.isEmpty {
                Text("None yet").foregroundStyle(.secondary)
            }
            ForEach(Array(received.enumerated()), id: \.offset) { _, line in
                Text(line).accessibilityIdentifier("received")
            }
        }
    }
}
