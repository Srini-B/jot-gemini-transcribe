// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#if os(macOS)
import AppKit

/// Whether a word is ordinary language, found in the system spelling
/// dictionary. Auto-learn keeps only words that are not: names, product
/// terms, jargon. Editing "They" to "we" or "There's" to "there's" fixes
/// wording or case; it does not teach the model a new word.
///
/// Words are checked in lowercase. Capitalized, the spell checker accepts
/// many unknown words as possible proper nouns ("Kubernetes", "RevenueCat");
/// lowercase, it knows "there's" and "john" but not "kubernetes", "voiceiq"
/// or "priya" (measured 2026-09-28 with macOS's English dictionaries).
@MainActor
enum CommonWords {
    /// The user's English variant first (en_IN, en_GB, …), then "en", so both
    /// "colour" and "color" count as ordinary.
    private static let languages: [String] = {
        let preferred = NSSpellChecker.shared.userPreferredLanguages.first { $0.hasPrefix("en") }
        return [preferred, "en"].compactMap { $0 }.reduce(into: []) { list, language in
            if !list.contains(language) { list.append(language) }
        }
    }()

    /// True when every word in `text` is in the spelling dictionary.
    static func isOrdinary(_ text: String) -> Bool {
        let words = text.lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .map { $0.trimmingCharacters(in: CharacterSet.alphanumerics.inverted.subtracting(CharacterSet(charactersIn: "'-"))) }
            .filter { !$0.isEmpty }
        guard !words.isEmpty else { return true }
        return words.allSatisfy(isKnown)
    }

    private static func isKnown(_ word: String) -> Bool {
        let checker = NSSpellChecker.shared
        return languages.contains { language in
            checker.checkSpelling(of: word, startingAt: 0, language: language, wrap: false,
                                  inSpellDocumentWithTag: 0, wordCount: nil).location == NSNotFound
        }
    }
}
#endif
