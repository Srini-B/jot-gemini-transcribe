// Copyright 2026 Google LLC
// Licensed under the Apache License, Version 2.0.

import Foundation

/// Fresh web context for Ask Anything.
///
/// Gemini decides whether the request needs current information and, if so,
/// what to search for (one short flash call). TinyFish then searches, the top
/// pages are fetched as Markdown, and the trimmed text is handed back to be
/// placed in the Ask Anything prompt. Any failure returns `nil` and the answer
/// proceeds without web context; a missing TinyFish key skips all of it.
public struct WebContext: Sendable, Equatable {
    public struct Source: Sendable, Equatable {
        public let title: String
        public let url: String
        public let text: String
    }

    public let query: String
    public let sources: [Source]

    /// Budget per page and overall, in characters. Ask Anything answers are
    /// short; three trimmed pages are plenty and keep the prompt small.
    static let perPageLimit = 6_000
    static let maxSources = 3
    static let fetchBudgetSeconds: TimeInterval = 8
    static let noSearchToken = "NONE"

    /// Prompt body shown to the model. Sources are numbered so the answer can
    /// cite them.
    public var promptBlock: String {
        let entries = sources.enumerated().map { index, source in
            """
            <source id="\(index + 1)" title="\(source.title)" url="\(source.url)">
            \(source.text)
            </source>
            """
        }
        return """
        <web_context query="\(query)">
        \(entries.joined(separator: "\n"))
        </web_context>
        """
    }

    public static func gather(
        instruction: String,
        selectedText: String?,
        gemini: GeminiClient,
        tinyFish: TinyFishClient,
        config: GeminiConfig
    ) async -> WebContext? {
        let query: String
        do {
            let response = try await gemini.cleanup(
                prompt: PromptV1.webSearchQueryPrompt(instruction: instruction, selectedText: selectedText),
                model: config.cleanupModel,
                endpoint: config.endpoint,
                deadline: 8
            )
            query = response.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'`"))
        } catch {
            Log.transcription.info("web context: query decision failed, skipping")
            return nil
        }
        guard !query.isEmpty, query.uppercased() != noSearchToken else {
            Log.transcription.info("web context: not needed")
            return nil
        }
        do {
            let results = try await tinyFish.search(query)
            let urls = Array(results.map(\.url).prefix(maxSources))
            guard !urls.isEmpty else { return nil }
            // Page text is a bonus over the snippets; a slow site must not hold
            // the answer, so a fetch past the budget falls back to snippets.
            let pages = (try? await GeminiClient.withDeadline(seconds: fetchBudgetSeconds) {
                try await tinyFish.fetch(urls, timeoutMs: Int(fetchBudgetSeconds * 1000) - 1_000)
            }) ?? []
            if pages.isEmpty { Log.transcription.info("web context: fetch missed the budget, using snippets") }
            let byURL = Dictionary(pages.map { ($0.url, $0) }, uniquingKeysWith: { first, _ in first })
            let sources: [Source] = results.prefix(maxSources).map { result in
                let page = byURL[result.url]
                let text = page?.text ?? result.snippet
                return Source(
                    title: page?.title.isEmpty == false ? page!.title : result.title,
                    url: result.url,
                    text: String(text.prefix(perPageLimit))
                )
            }
            Log.transcription.info("web context: \(sources.count) sources for \(query, privacy: .private)")
            return WebContext(query: query, sources: sources)
        } catch {
            Log.transcription.error("web context: tinyfish failed \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}
