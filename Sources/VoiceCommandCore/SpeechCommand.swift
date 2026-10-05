//
//  SpeechCommand.swift
//  playground
//
//  Voice command vocabulary and parser. Pure value types, no Speech framework:
//  this is what the unit tests exercise. Vocabulary lifted from the `voice`
//  branch (`CommandCenter` synonyms); dispatch semantics from d2caa20.
//

import Foundation

nonisolated enum SpeechCommand: Equatable, Sendable {
    case open(recipe: String)
    /// `name` is whatever followed the phrase; may be empty.
    case newRecipe(name: String)
    case addIngredient
    case removeIngredient
}

nonisolated struct CommandInterpreter: Sendable {
    var triggerWord = "genie"
    /// What the recognizer actually returns for "genie" in practice. Observed on
    /// device: "jean", "jeannie", "ginny"; without these the trigger rarely fires.
    static let triggerAliases = ["genie", "jeanie", "jeannie", "jean", "ginny", "jeni", "jenny"]
    /// Lowercased recipe names the user can `open`.
    var recipeNames: [String] = []

    static let openVerbs = ["open", "show", "view"]
    static let newRecipePhrases = ["new recipe", "create recipe", "add recipe"]
    static let addIngredientPhrases = ["add ingredient"]
    static let removeIngredientPhrases = ["remove ingredient"]

    /// Everything the recognizer should bias toward (`SFSpeechRecognitionRequest.contextualStrings`).
    var contextualStrings: [String] {
        [triggerWord]
            + Self.newRecipePhrases + Self.addIngredientPhrases + Self.removeIngredientPhrases
            + recipeNames.flatMap { name in Self.openVerbs.map { "\($0) \(name)" } }
    }

    func containsTrigger(_ text: String) -> Bool {
        let t = text.lowercased()
        return Self.triggerAliases.contains(where: t.contains)
    }

    /// Index just past the last trigger occurrence, so a long transcript is parsed
    /// from the most recent trigger rather than the first.
    private func afterLastTrigger(_ text: String) -> String {
        var best: String.Index?
        for alias in Self.triggerAliases {
            var search = text.startIndex..<text.endIndex
            while let r = text.range(of: alias, range: search) {
                if best == nil || r.upperBound > best! { best = r.upperBound }
                guard r.upperBound < text.endIndex else { break }
                search = r.upperBound..<text.endIndex
            }
        }
        guard let best else { return text }
        return String(text[best...])
    }

    /// First command found in `text`. Text after the trigger word (if present) is what gets parsed.
    func command(in text: String) -> SpeechCommand? {
        var t = afterLastTrigger(text.lowercased())
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }

        if Self.removeIngredientPhrases.contains(where: t.contains) { return .removeIngredient }
        if Self.addIngredientPhrases.contains(where: t.contains) { return .addIngredient }

        // Longest name first so "corn salad" beats "corn".
        for name in recipeNames.sorted(by: { $0.count > $1.count }) {
            for verb in Self.openVerbs where t.contains("\(verb) \(name)") {
                return .open(recipe: name)
            }
        }

        for phrase in Self.newRecipePhrases {
            if let r = t.range(of: phrase) {
                let name = t[r.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                return .newRecipe(name: name)
            }
        }
        return nil
    }
}
