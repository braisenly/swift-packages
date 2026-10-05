//
//  CommandInterpreterTests.swift
//  VoiceCommandCoreTests
//
//  Ported from playground (playgroundTests.swift `CommandInterpreting`,
//  `TriggerHandling`; VoiceCommandCharacterizationTests.swift phrase table).
//

import Testing
import VoiceCommandCore

struct CommandInterpreting {
    let interp = CommandInterpreter(recipeNames: ["grilled corn", "corn salad"])

    @Test func trigger() {
        #expect(interp.containsTrigger("Hey Genie"))
        #expect(!interp.containsTrigger("hello"))
    }

    @Test func openPrefersLongestName() {
        #expect(interp.command(in: "genie open corn salad") == .open(recipe: "corn salad"))
        #expect(interp.command(in: "show grilled corn please") == .open(recipe: "grilled corn"))
        #expect(interp.command(in: "open pizza") == nil)
    }

    @Test func newRecipeCapturesName() {
        #expect(interp.command(in: "new recipe chocolate cake") == .newRecipe(name: "chocolate cake"))
        #expect(interp.command(in: "create recipe") == .newRecipe(name: ""))
    }

    @Test func ingredientsAndSilence() {
        #expect(interp.command(in: "add ingredient") == .addIngredient)
        #expect(interp.command(in: "remove ingredient") == .removeIngredient)
        #expect(interp.command(in: "genie") == nil)
        #expect(interp.command(in: "") == nil)
    }

    @Test func contextualStringsCoverVocabulary() {
        let c = interp.contextualStrings
        #expect(c.contains("genie") && c.contains("open corn salad") && c.contains("new recipe"))
    }
}

struct TriggerHandling {
    let interp = CommandInterpreter(recipeNames: ["grilled corn", "corn salad"])

    @Test func acceptsMisheardTriggers() {
        // The recognizer returns these for "genie" in practice.
        #expect(interp.containsTrigger("Jean"))
        #expect(interp.containsTrigger("Jeannie open corn salad"))
        #expect(!interp.containsTrigger("open corn salad"))
    }

    @Test func parsesFromTheLastTrigger() {
        // A long trigger-phase transcript must not resolve to a stale command.
        let rambling = "genie open grilled corn and then we talked for ages genie open corn salad"
        #expect(interp.command(in: rambling) == .open(recipe: "corn salad"))
    }
}

struct CommandInterpreterPhraseTable {
    let interp = CommandInterpreter(recipeNames: ["pancakes", "waffles"])

    @Test func triggerWordAndAliases() {
        #expect(interp.triggerWord == "genie")
        #expect(CommandInterpreter.triggerAliases == ["genie", "jeanie", "jeannie", "jean", "ginny", "jeni", "jenny"])
    }

    @Test func everyOpenVerb() {
        for verb in ["open", "show", "view"] {
            #expect(interp.command(in: "genie \(verb) pancakes") == .open(recipe: "pancakes"))
        }
    }

    @Test func everyNewRecipePhrase() {
        for phrase in ["new recipe", "create recipe", "add recipe"] {
            #expect(interp.command(in: "genie \(phrase) Waffles") == .newRecipe(name: "waffles"))
        }
    }

    @Test func removeIngredientWinsOverAdd() {
        #expect(interp.command(in: "add ingredient remove ingredient") == .removeIngredient)
    }

    @Test func ingredientCommandsWinOverOpen() {
        #expect(interp.command(in: "open pancakes add ingredient") == .addIngredient)
    }

    @Test func unknownRecipeIsNotACommand() {
        #expect(interp.command(in: "genie open pizza") == nil)
    }
}
