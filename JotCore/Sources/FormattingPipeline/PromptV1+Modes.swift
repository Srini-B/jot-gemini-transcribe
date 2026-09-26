// Copyright 2026 Google LLC
// Licensed under the Apache License, Version 2.0.

import Foundation

public extension PromptV1 {
    static func askAnythingPrompt(
        instruction: String,
        selectedText: String?,
        tone: PromptV1.ToneCategory,
        vocabulary: [String]
    ) -> String {
        let selection = selectedText?.trimmingCharacters(in: .whitespacesAndNewlines)
        let context = selection.map { "Apply the instruction to this selected text:\n<selection>\n\($0)\n</selection>" }
            ?? "There is no selected text. Answer or produce the requested content directly."
        return """
        You are a direct writing assistant. The spoken transcript below is an instruction.
        \(context)
        Output only the resulting text with no preamble. Be concise and use plain text. Use Markdown only when the user asks for a list or code.
        Match this tone: \(tone.rawValue).
        Preserve these names and terms when relevant: \(vocabulary.joined(separator: ", ")).
        <instruction>
        \(instruction)
        </instruction>
        """
    }

    static func translatePrompt(raw: String, target: String, vocabulary: [String]) -> String {
        """
        Detect the transcript's source language and translate it into \(target). Preserve meaning, formatting, names, numbers, and intent. Lightly remove spoken fillers. Output only the translation.
        If you cannot produce a translation in \(target), output exactly <<UNTRANSLATABLE>> and nothing else.
        Preserve these names and terms when relevant: \(vocabulary.joined(separator: ", ")).
        <transcript>
        \(raw)
        </transcript>
        """
    }
}
