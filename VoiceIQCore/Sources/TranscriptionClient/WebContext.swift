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
    /// MEASURED 2026-09-27: "current price of Bitcoin" took ~15 s end to end,
    /// most of it the page fetch and the answer model reading 18 k characters
    /// of page text. Snippets already carry the fact for a lookup like that;
    /// the fetch is capped so it adds little when pages are slow, and pages
    /// are trimmed so the answer call stays short.
    static let perPageLimit = 3_000
    static let maxSources = 3
    static let fetchBudgetSeconds: TimeInterval = 4
    static let noSearchToken = "NONE"
    static let recentPrefix = "RECENT:"
    /// One week. Wide enough that a Monday question about the weekend still
    /// finds coverage; narrow enough to skip last year's article on the topic.
    static let recentWindowMinutes = 7 * 24 * 60

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

    /// The model's answer to "does this need a search, and must it be fresh?"
    struct Decision: Equatable {
        let query: String
        let recent: Bool

        init(_ response: String) {
            var text = response.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'`"))
            recent = text.uppercased().hasPrefix(WebContext.recentPrefix)
            if recent { text = String(text.dropFirst(WebContext.recentPrefix.count)) }
            query = text.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'`"))
        }
    }

    public static func gather(
        instruction: String,
        selectedText: String?,
        gemini: GeminiClient,
        tinyFish: TinyFishClient,
        config: GeminiConfig
    ) async -> WebContext? {
        let decision: Decision
        do {
            let response = try await gemini.cleanup(
                prompt: PromptV1.webSearchQueryPrompt(instruction: instruction, selectedText: selectedText),
                model: config.cleanupModel,
                endpoint: config.endpoint,
                deadline: 8,
                stage: .webQuery
            )
            decision = Decision(response)
        } catch {
            Log.transcription.info("web context: query decision failed, skipping")
            return nil
        }
        guard !decision.query.isEmpty, decision.query.uppercased() != noSearchToken else {
            Log.transcription.info("web context: not needed")
            return nil
        }
        let query = decision.query
        do {
            // A fresh-only search can come back empty for a niche topic; the
            // unfiltered search is the fallback rather than no answer.
            var results = try await tinyFish.search(query, recencyMinutes: decision.recent ? recentWindowMinutes : nil)
            if results.isEmpty, decision.recent {
                Log.transcription.info("web context: no recent results, widening")
                results = try await tinyFish.search(query)
            }
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
