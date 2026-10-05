//
//  VoiceCommandControllerTests.swift
//  VoiceCommandCoreTests
//
//  The voice command state machine, driven through the ports with a scripted
//  transcriber. These pin the phase transitions the Gate 0 baseline could not
//  reach without live audio.
//

import Testing
import Foundation
import VoiceCommand
import VoiceCommandTesting

@MainActor
struct VoiceCommandStateMachine {
    let transcriber = ScriptedTranscriber()

    func makeController(
        authorization: VoiceAuthorization = .authorized,
        clock: any Clock<Duration> = ContinuousClock()
    ) -> VoiceCommandController {
        let controller = VoiceCommand.makeController(
            dependencies: .scripted(transcriber: transcriber, authorization: authorization, clock: clock)
        )
        controller.setVocabulary(recipeNames: ["Pancakes", "Grilled Corn"])
        return controller
    }

    /// Lets the countdown task run until `condition` holds (bounded).
    func settle(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() { await Task.yield() }
    }

    @Test func startListensForTrigger() async {
        let controller = makeController()
        await controller.start()
        #expect(controller.phase == .waitingForTrigger)
        #expect(controller.isListening)
        #expect(transcriber.startCount == 1)
        #expect(transcriber.lastContextualStrings.contains("open pancakes"))
    }

    @Test(arguments: [
        (VoiceAuthorization.denied, "Speech recognition denied in Settings."),
        (.restricted, "Speech recognition restricted on this device."),
        (.notDetermined, "Speech recognition not authorized."),
        (.unknown, "Unknown speech authorization status."),
    ])
    func refusedAuthorizationFails(_ authorization: VoiceAuthorization, message: String) async {
        let controller = makeController(authorization: authorization)
        await controller.start()
        #expect(controller.phase == .idle)
        #expect(controller.errorMessage == message)
        #expect(transcriber.startCount == 0)
    }

    @Test func unavailableRecognizerFails() async {
        transcriber.isAvailable = false
        let controller = makeController()
        await controller.start()
        #expect(controller.phase == .idle)
        #expect(controller.errorMessage == "Speech recognizer not available.")
    }

    @Test func audioSetupFailureFails() async {
        struct Boom: LocalizedError { var errorDescription: String? { "no input" } }
        transcriber.startError = Boom()
        let controller = makeController()
        await controller.start()
        #expect(controller.phase == .idle)
        #expect(controller.errorMessage == "Audio setup failed: no input")
    }

    @Test func startWhileListeningIsIgnored() async {
        let controller = makeController()
        await controller.start()
        await controller.start()
        #expect(transcriber.startCount == 1)
    }

    @Test func triggerOpensCommandWindow() async {
        let controller = makeController()
        await controller.start()
        transcriber.send(.text("hey genie", isFinal: false))
        #expect(controller.phase == .listeningForCommands)
        #expect(controller.transcript.isEmpty)
        #expect(transcriber.startCount == 2)
        await settle { controller.countdownRemaining == 6 }
        #expect(controller.countdownRemaining == 6)
        controller.stop()
    }

    @Test func commandIsDeliveredThenTriggerResumes() async {
        let controller = makeController()
        await controller.start()
        transcriber.send(.text("genie", isFinal: false))
        transcriber.send(.text("open pancakes", isFinal: false))
        #expect(controller.command == .open(recipe: "pancakes"))
        #expect(controller.phase == .waitingForTrigger)
        #expect(controller.countdownRemaining == 0)
    }

    @Test func newRecipeWaitsForFinalUtterance() async {
        let controller = makeController()
        await controller.start()
        transcriber.send(.text("genie", isFinal: false))
        transcriber.send(.text("new recipe waff", isFinal: false))
        #expect(controller.command == nil)
        #expect(controller.phase == .listeningForCommands)
        transcriber.send(.text("new recipe waffles", isFinal: true))
        #expect(controller.command == .newRecipe(name: "waffles"))
        controller.stop()
    }

    @Test func finalUtteranceWithoutCommandReturnsToTrigger() async {
        let controller = makeController()
        await controller.start()
        transcriber.send(.text("genie", isFinal: false))
        transcriber.send(.text("what time is it", isFinal: true))
        #expect(controller.command == nil)
        #expect(controller.phase == .waitingForTrigger)
    }

    @Test func expiredWindowWithoutCommandReturnsToTrigger() async {
        let controller = makeController(clock: ImmediateClock())
        await controller.start()
        transcriber.send(.text("genie", isFinal: false))
        await settle { controller.phase == .waitingForTrigger }
        #expect(controller.phase == .waitingForTrigger)
        #expect(controller.command == nil)
        #expect(controller.countdownRemaining == 0)
    }

    @Test func expiredWindowDeliversPendingCommand() async {
        let controller = makeController(clock: ImmediateClock())
        await controller.start()
        transcriber.send(.text("genie", isFinal: false))
        // A not-yet-final "new recipe" is held until the window closes.
        transcriber.send(.text("new recipe soup", isFinal: false))
        await settle { controller.command != nil }
        #expect(controller.command == .newRecipe(name: "soup"))
        #expect(controller.phase == .waitingForTrigger)
    }

    @Test func idleTranscriptRestartsWhenFinalOrTooLong() async {
        let controller = makeController()
        await controller.start()
        transcriber.send(.text("just chatting", isFinal: true))
        #expect(transcriber.startCount == 2)
        transcriber.send(.text(String(repeating: "x", count: 121), isFinal: false))
        #expect(transcriber.startCount == 3)
        transcriber.send(.text(String(repeating: "x", count: 120), isFinal: false))
        #expect(transcriber.startCount == 3)
        #expect(controller.phase == .waitingForTrigger)
    }

    @Test func recognitionFailureShowsErrorAndKeepsListening() async {
        let controller = makeController()
        await controller.start()
        transcriber.send(.failure("Recognition failed"))
        #expect(controller.errorMessage == "Recognition failed")
        #expect(controller.phase == .waitingForTrigger)
        #expect(transcriber.startCount == 2)
    }

    @Test func stopReturnsToIdleAndStopsAudio() async {
        let controller = makeController()
        await controller.start()
        transcriber.send(.text("genie", isFinal: false))
        controller.stop()
        #expect(controller.phase == .idle)
        #expect(controller.transcript.isEmpty)
        #expect(controller.countdownRemaining == 0)
        #expect(!transcriber.isRunning)
    }
}
