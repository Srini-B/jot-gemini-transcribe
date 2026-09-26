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

import AVFoundation
import Foundation

/// The transcription pipeline.
///
///   CAF → FLAC → interactions (mode: smart, custom_vocabulary)
///       → [optional] flash-lite cleanup for per-app tone → validation gate
///       → ReplacementEngine → inserted text.
///
/// The model now does filler removal, self-correction collapse and list
/// formatting itself, so the default path is ONE call. The cleanup pass survives
/// as an opt-in because it is the only thing that carries per-app tone.
///
/// Rules unchanged: one silent retry on transient transcribe failures; cleanup
/// has a hard deadline and NEVER blocks a good transcript; every failure is a
/// typed TranscriptionError mapping to the failure matrix.
public struct GeminiTranscriptionService: TranscriptionServicing {
    static let untranslatableToken = "<<UNTRANSLATABLE>>"
    private let client: GeminiClient
    private let settings: SettingsStore

    /// Cleanup budget. The pass reads the whole transcript and writes it back, so
    /// the budget grows with the text: a one-line dictation gets ~12 s, a
    /// ten-minute one (~8k characters) ~35 s. Capped so a stalled request still
    /// falls back to the raw transcript in bounded time.
    /// MEASURED 2026-09-26: the full cleanup prompt (rules + seed instructions,
    /// ~15 k characters) on gemini-3.8-flash at thinkingLevel low took 1.7–4.9 s
    /// for a 170-character transcript, with or without a screenshot. The old
    /// 3 s floor tripped "cleanup unavailable (timeout)" on ordinary dictations,
    /// which pasted RAW text and made every formatting rule look ignored.
    static func cleanupDeadline(forCharacters count: Int) -> TimeInterval {
        min(60, 12 + Double(count) / 350)
    }

    public init(client: GeminiClient, settings: SettingsStore = SettingsStore()) {
        self.client = client
        self.settings = settings
    }

    public func transcribe(audioURL: URL, durationSeconds: Double, context: DictationContext) async throws -> TranscriptionResult {
        let config = settings.geminiConfig
        let policy = settings.formattingPolicy
        // Read once per dictation: a toggle flipped mid-flight must not change
        // the rules this transcript is being produced under.
        let vocabulary = Self.vocabularyIfEnabled()

        // One request per chunk. A short dictation is one chunk, so this is the
        // old single-request path for everything under ten minutes.
        let ranges = try AudioChunker.ranges(cafURL: audioURL)
        if ranges.count > 1 {
            Log.transcription.info("long recording (\(Int(durationSeconds))s) split into \(ranges.count) chunks")
        }
        var pieces: [String] = []
        for (index, range) in ranges.enumerated() {
            let flacData = try encodeChunk(audioURL: audioURL, range: range, index: index)
            let seconds = durationSeconds * Double(range.count) / Double(max(1, ranges.reduce(0) { $0 + $1.count }))
            let deadline = TimeoutPolicy.overallDeadline(audioDuration: seconds)
            var raw = try await transcribeWithRetry(
                flacData: flacData, config: config, policy: policy,
                vocabulary: vocabulary, deadline: deadline
            )
            var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty, seconds >= 0.6 {
                // F9a second chance: an empty result on real audio is sometimes model
                // nondeterminism — one re-send before surfacing anything (audit L25).
                Log.transcription.info("empty transcript on \(String(format: "%.1f", seconds))s audio — one re-send")
                // NB: goes through the same policy-aware call as the primary path.
                // Sending this one down the old endpoint would leave a rare branch
                // silently on a different pipeline.
                raw = (try? await sendTranscribe(
                    flacData: flacData, config: config, policy: policy,
                    vocabulary: vocabulary, deadline: deadline
                )) ?? ""
                trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if !trimmed.isEmpty { pieces.append(trimmed) }
        }

        let trimmedRaw = pieces.joined(separator: " ")
        guard !trimmedRaw.isEmpty else {
            // The coordinator classifies silence vs dropped-transcript by energy.
            throw TranscriptionError.emptyTranscript
        }

        if context.mode != .dictate {
            let cleaned = try await transform(raw: trimmedRaw, context: context, config: config)
            return TranscriptionResult(
                rawTranscript: trimmedRaw,
                cleanedTranscript: cleaned,
                modelID: "\(config.transcribeModel)/\(policy.mode.rawValue)+\(config.cleanupModel)"
            )
        }

        guard policy.cleanupPass else {
            // Dictionary rules are a HARD guarantee — they apply on every path
            // (audit L9). The gate is deliberately NOT run here: with no second
            // model there is no independent reference, and validate(raw:X, cleaned:X)
            // passes trivially, so running it would be theatre rather than safety.
            let rules = DictionaryStore().replacementRules()
            let text = ReplacementEngine.apply(rules, to: trimmedRaw)
            return TranscriptionResult(
                rawTranscript: trimmedRaw,
                cleanedTranscript: text,
                modelID: "\(config.transcribeModel)/\(policy.mode.rawValue)"
            )
        }

        let cleaned = await cleanupOrFallback(raw: trimmedRaw, context: context, config: config)
        return TranscriptionResult(
            rawTranscript: trimmedRaw,
            cleanedTranscript: cleaned,
            modelID: "\(config.transcribeModel)/\(policy.mode.rawValue)+\(config.cleanupModel)"
        )
    }

    /// The cleanup stage on its own, for transcripts the live stream produced.
    /// Live output has already had dictionary rules applied by `LiveTranscriber`;
    /// the pass here works from the raw transcript so the gate has a true
    /// reference, and re-applies the rules on whatever comes back.
    public func polish(_ result: TranscriptionResult, context: DictationContext) async -> TranscriptionResult {
        guard context.mode == .dictate else { return result }
        guard settings.formattingPolicy.cleanupPass else { return result }
        let config = settings.geminiConfig
        let raw = result.rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return result }
        let cleaned = await cleanupOrFallback(raw: raw, context: context, config: config)
        return TranscriptionResult(
            rawTranscript: result.rawTranscript,
            cleanedTranscript: cleaned,
            modelID: "\(result.modelID)+\(config.cleanupModel)"
        )
    }

    // MARK: - Stages

    private func transform(raw: String, context: DictationContext, config: GeminiConfig) async throws -> String {
        let dictionary = DictionaryStore()
        let prompt: String
        switch context.mode {
        case .dictate:
            return raw
        case .askAnything(let selectedText):
            var webContext: WebContext?
            if KeychainStore.loadTinyFishKey() != nil {
                webContext = await WebContext.gather(
                    instruction: raw,
                    selectedText: selectedText,
                    gemini: client,
                    tinyFish: TinyFishClient(apiKey: { KeychainStore.loadTinyFishKey() }),
                    config: config
                )
            }
            prompt = PromptV1.askAnythingPrompt(
                instruction: raw,
                selectedText: selectedText,
                tone: PromptV1.toneCategory(forBundleID: context.targetAppBundleID),
                vocabulary: dictionary.sanitizedVocabulary(),
                webContext: webContext
            )
        case .translate(let target):
            prompt = PromptV1.translatePrompt(
                raw: raw, target: target, vocabulary: dictionary.sanitizedVocabulary()
            )
        }
        let response = try await client.cleanup(
            prompt: prompt,
            model: config.cleanupModel,
            endpoint: config.endpoint,
            // Web context can make the prompt far larger than the transcript;
            // the model has to read it all, so the budget follows the prompt.
            deadline: Self.cleanupDeadline(forCharacters: max(raw.count, prompt.count / 3))
        )
        let cleaned = ValidationGate.stripArtifacts(response).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw TranscriptionError.emptyTranscript }
        if case .translate = context.mode, cleaned == Self.untranslatableToken {
            throw TranscriptionError.emptyTranscript
        }
        return cleaned
    }

    private func encodeChunk(audioURL: URL, range: Range<AVAudioFramePosition>, index: Int) throws -> Data {
        let flacURL = audioURL.deletingLastPathComponent().appendingPathComponent("audio-\(index).flac")
        let encoded = try FLACEncoder.encode(cafURL: audioURL, flacURL: flacURL, frameRange: range)
        Log.transcription.info("FLAC chunk \(index) \(encoded.byteCount) bytes in \(Int(encoded.encodeSeconds * 1000))ms")
        let data = try Data(contentsOf: encoded.url)
        // The FLAC is derived data (re-encoded from the CAF on any retry) — once
        // it's in memory the file is pure duplication. Storage policy: the CAF is
        // the only audio artifact that persists.
        try? FileManager.default.removeItem(at: encoded.url)
        return data
    }

    /// Vocabulary is suppressed once it has PROVABLY broken a request.
    ///
    /// Keyed on the vocabulary itself rather than a bare flag: editing the
    /// Dictionary changes the key and we try again, so one bad entry cannot
    /// disable the feature until relaunch with nothing telling the user why.
    private static let vocabularySuppressed = Suppression()
    final class Suppression: @unchecked Sendable {
        private let lock = NSLock()
        private var blocked: Int?
        func isBlocked(_ vocabulary: [String]) -> Bool {
            lock.lock(); defer { lock.unlock() }
            return blocked != nil && blocked == vocabulary.hashValue
        }
        func block(_ vocabulary: [String]) {
            lock.lock(); blocked = vocabulary.hashValue; lock.unlock()
        }
    }

    private static func vocabularyIfEnabled() -> [String] {
        let vocabulary = DictionaryStore().sanitizedVocabulary()
        return vocabularySuppressed.isBlocked(vocabulary) ? [] : vocabulary
    }

    /// The ONE place a transcription request is sent. Every caller — primary,
    /// silent retry, and the empty-transcript second chance — goes through here.
    private func sendTranscribe(
        flacData: Data, config: GeminiConfig, policy: SettingsStore.FormattingPolicy,
        vocabulary: [String], deadline: TimeInterval
    ) async throws -> String {
        // The transport decision lives in ONE place so the fail-open retry below
        // cannot silently switch endpoints half way through a recovery.
        func send(_ terms: [String]) async throws -> String {
            if settings.usesLegacyTranscribeEndpoint {
                // Verbatim only — `mode` returns an empty transcript on this
                // endpoint. The tone pass, if enabled, still runs on top.
                return try await client.transcribe(
                    flacData: flacData, model: config.transcribeModel,
                    endpoint: config.endpoint, deadline: deadline, customVocabulary: terms
                )
            }
            return try await client.transcribeInteraction(
                audio: flacData, model: config.transcribeModel, endpoint: config.endpoint,
                mode: policy.mode, customVocabulary: terms, deadline: deadline
            )
        }

        do {
            return try await send(vocabulary)
        } catch TranscriptionError.badRequest(let message) where !vocabulary.isEmpty {
            // Fail open. badRequest is deliberately terminal everywhere else, but
            // one strange dictionary entry must never be able to break a user's
            // own dictation. Covers BOTH transports — the legacy endpoint carries
            // vocabulary too.
            Log.transcription.error("transcribe rejected with vocabulary (\(message, privacy: .private)) — retrying without it")
            let text = try await send([])
            // Only latch once the vocabulary-free retry SUCCEEDS. If it also
            // fails, the vocabulary was innocent — and a bad API key returns 400
            // here, not 401, so latching eagerly would disable the Dictionary for
            // the rest of the launch over an auth problem.
            Self.vocabularySuppressed.block(vocabulary)
            return text
        }
    }

    private func transcribeWithRetry(
        flacData: Data, config: GeminiConfig, policy: SettingsStore.FormattingPolicy,
        vocabulary: [String], deadline: TimeInterval
    ) async throws -> String {
        do {
            return try await sendTranscribe(
                flacData: flacData, config: config, policy: policy,
                vocabulary: vocabulary, deadline: deadline
            )
        } catch let error as TranscriptionError {
            switch error {
            case .network, .timeout:
                // One silent retry for transient classes (audio is safe on disk).
                Log.transcription.info("transcribe retrying after \(String(describing: error), privacy: .public)")
                try await Task.sleep(nanoseconds: 500_000_000)
                return try await sendTranscribe(
                    flacData: flacData, config: config, policy: policy,
                    vocabulary: vocabulary, deadline: deadline
                )
            default:
                throw error
            }
        }
    }

    private func cleanupOrFallback(raw: String, context: DictationContext, config: GeminiConfig) async -> String {
        let tone = PromptV1.toneCategory(forBundleID: context.targetAppBundleID)
        let dictionary = DictionaryStore()
        let prompt = PromptV1.cleanupPrompt(
            raw: raw,
            tone: tone,
            vocabulary: dictionary.sanitizedVocabulary(),
            spellings: dictionary.spellings(),
            instructions: settings.customInstructions,
            imagesAttached: !context.screenshots.isEmpty
        )
        do {
            let deadline = min(
                60,
                Self.cleanupDeadline(forCharacters: raw.count) + Double(context.screenshots.count * 2)
            )
            let response = try await client.cleanup(
                prompt: prompt, images: context.screenshots, model: config.cleanupModel,
                endpoint: config.endpoint, deadline: deadline
            )
            let cleaned = ValidationGate.stripArtifacts(response)
            let verdict = ValidationGate.validate(raw: raw, cleaned: cleaned)
            guard verdict.accepted else {
                let trips = settings.recordGateTrip()
                Log.transcription.warning("cleanup gate REJECTED (\(verdict.reason ?? "?", privacy: .public), trip #\(trips) in 24h) — inserting raw")
                autoDegradeIfNeeded(trips: trips)
                return ReplacementEngine.apply(dictionary.replacementRules(), to: raw)
            }
            // The dictionary's hard guarantee: explicit wrong→right rules always win.
            return ReplacementEngine.apply(dictionary.replacementRules(), to: cleaned)
        } catch {
            // Deadline miss / network hiccup on cleanup never costs the dictation —
            // and the dictionary guarantee still holds (audit L9).
            Log.transcription.info("cleanup unavailable (\(String(describing: error), privacy: .public)) — inserting raw")
            return ReplacementEngine.apply(dictionary.replacementRules(), to: raw)
        }
    }

    /// F11 auto-degrade (audit L10): three gate trips in 24h means cleanup can't
    /// be trusted right now — switch to exact transcription until re-enabled.
    private func autoDegradeIfNeeded(trips: Int) {
        guard trips >= 3, settings.smartCleanupPassEnabled else { return }
        settings.setSmartCleanupPass(false)
        NotificationCenter.default.post(name: .gtSmartFormattingAutoDegraded, object: nil)
        Log.transcription.warning("cleanup unreliable (3 gate trips in 24h) — tone pass auto-disabled; smart transcription unaffected")
    }
}
