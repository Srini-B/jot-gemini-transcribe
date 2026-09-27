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

import Foundation

/// Turns a meeting's mic and system tracks into one speaker-labelled transcript.
///
/// Only stretches with speech are sent, as one timeline of both tracks
/// (`CallAudio`). The meeting is cut into windows of speech; every window
/// after the first starts with reference clips of the speakers already found,
/// which is how a speaker keeps one id across a two-hour call
/// (`SpeakerLinker`). The note owner is whoever speaks from the mic alone.
/// Finished windows are cached beside the audio, so a retry after a rate
/// limit or a crash never pays for the same audio twice.
///
/// MEASURED 2026-09-27. Transcribing the two tracks separately was tried
/// first and dropped: a request holding only the far side, with its long
/// silences cut out, made both models return a fraction of the speech (29
/// segments for ten minutes of a call through the flash model).
public struct MeetingTranscriber: Sendable {
    public struct Models: Sendable {
        public var transcribe: String
        public var flash: String
        public init(transcribe: String, flash: String) { self.transcribe = transcribe; self.flash = flash }
    }

    private let client: GeminiClient
    private let models: Models
    private let endpoint: URL
    private let providers: @Sendable () -> [ModelProvider]
    private let sleep: @Sendable (TimeInterval) async throws -> Void

    public init(client: GeminiClient, models: Models, endpoint: URL,
                providers: @escaping @Sendable () -> [ModelProvider],
                sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) }) {
        self.client = client; self.models = models; self.endpoint = endpoint; self.providers = providers; self.sleep = sleep
    }

    /// Seconds of speech per request. Diarized requests are capped at 30
    /// minutes of audio; ten keeps a Tier 1 key (10,000 audio tokens a minute,
    /// 25 tokens a second) to about one minute of waiting per window. The
    /// flash model on the gateway path drops speech from long audio, so it
    /// gets shorter windows. MEASURED 2026-09-27 on a 30-minute call: native
    /// at 600 s gave 907 words, the gateway at 150 s gave 807, and the gateway
    /// at 600 s on one track gave 29 segments for ten minutes of speech.
    static func windowSpeech(_ via: ModelProvider?) -> Double { via == .gemini ? 600 : 150 }
    /// A Tier 1 key needs about one minute of waiting per window; a two-hour
    /// call has twenty windows.
    static let rateLimitBudget: TimeInterval = 45 * 60
    static let cacheVersion = "v4"

    public func transcribe(folder: URL) async throws -> [TranscriptSegment] {
        let audio = CallAudio(mic: try TrackAudio(url: folder.appendingPathComponent("mic.caf")),
                              system: try TrackAudio(url: folder.appendingPathComponent("system.caf")))
        let window = Self.windowSpeech(providers().first)
        let cache = folder.appendingPathComponent("transcribe-\(Self.cacheVersion)-\(Int(window))", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        var budget = Self.rateLimitBudget
        let windows = Self.windows(audio.activeRegions(), speech: window)
        var words: [TimedWord] = []
        for (index, regions) in windows.enumerated() {
            let file = cache.appendingPathComponent("\(index).json")
            if let data = try? Data(contentsOf: file), let cached = try? JSONDecoder().decode([TimedWord].self, from: data) {
                words += cached; continue
            }
            let placed = try await transcribe(window: regions, audio: audio, known: words, budget: &budget,
                                              label: "window \(index + 1)/\(windows.count)")
            try JSONEncoder().encode(placed).write(to: file, options: .atomic)
            words += placed
        }
        if audio.isOnline { words = Self.markOwner(words, audio: audio) }
        return SpeakerLinker.turns(words.sorted { $0.start < $1.start }).map { turn in
            TranscriptSegment(speaker: turn.speaker, text: turn.text, chunkIndex: 0, start: turn.start, end: turn.end)
        }
    }

    /// The same test as `place`, over the whole meeting: an id heard mostly
    /// from the mic is the note owner even where single windows were too
    /// short to tell. MEASURED 2026-09-27 on the same two-person call: one id
    /// ended at 318 mic-only windows to 119 far-side ones after every window
    /// had been placed.
    static func markOwner(_ words: [TimedWord], audio: CallAudio) -> [TimedWord] {
        var totals: [String: (mic: Int, system: Int)] = [:]
        for word in words {
            let source = audio.sources(word.start...word.end)
            totals[word.speaker, default: (0, 0)].mic += source.mic
            totals[word.speaker, default: (0, 0)].system += source.system
        }
        let owners = Set(totals.filter { $0.value.mic >= 20 && $0.value.mic >= 2 * $0.value.system }.keys)
        return words.map { word in
            guard owners.contains(word.speaker) else { return word }
            var owned = word; owned.speaker = MeetingSpeaker.you; return owned
        }
    }

    /// Consecutive speech regions grouped into requests of about `windowSpeech` seconds each.
    static func windows(_ regions: [ClosedRange<Double>], speech windowSpeech: Double) -> [[ClosedRange<Double>]] {
        var out: [[ClosedRange<Double>]] = [], current: [ClosedRange<Double>] = [], total = 0.0
        for region in regions {
            if total + (region.upperBound - region.lowerBound) > windowSpeech, !current.isEmpty {
                out.append(current); current = []; total = 0
            }
            current.append(region); total += region.upperBound - region.lowerBound
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    /// Request words → meeting-time words under meeting-wide ids.
    ///
    /// On a call the track a label was heard on overrides the model: a label
    /// heard from the mic alone is the note owner, and a label heard from the
    /// far side never is. When the far side has had only one speaker so far,
    /// its one unmatched label is that speaker. MEASURED 2026-09-27 on a
    /// 30-minute two-person call through the gateway path: without this the
    /// two people swapped ids between windows; the owner's words were 422
    /// mic-only windows to 119 far-side ones.
    static func place(_ raw: [DiarizedWord], audio request: AssembledAudio, call: CallAudio, known: [TimedWord],
                      mapping linked: [String: String], idPrefix: String = "s") -> [TimedWord] {
        typealias Placed = (text: String, label: String, start: Double, end: Double)
        let placed: [Placed] = raw.compactMap { word in
            let label = word.speaker ?? ""
            guard let start = word.start else {
                // Untimed text (the API's no-annotation fallback) is kept as one turn.
                return (word.text, label, request.trackTime(request.bodyStart) ?? 0, request.trackTime(request.duration) ?? 0)
            }
            guard let begin = request.trackTime(start) else { return nil }
            return (word.text, label, begin, max(begin, request.trackTime(word.end ?? start) ?? begin))
        }
        var mapping = linked
        if call.isOnline {
            var sources: [String: (mic: Int, system: Int)] = [:]
            for word in placed {
                let source = call.sources(word.start...word.end)
                sources[word.label, default: (0, 0)].mic += source.mic
                sources[word.label, default: (0, 0)].system += source.system
            }
            for (label, source) in sources {
                if source.mic >= 10 && source.mic >= 2 * source.system { mapping[label] = MeetingSpeaker.you }
                else if mapping[label] == MeetingSpeaker.you { mapping[label] = nil }
            }
            let remote = Set(known.map(\.speaker)).subtracting([MeetingSpeaker.you])
            let unmatched = Set(placed.map(\.label)).filter { mapping[$0] == nil }
            if remote.count == 1, unmatched.count == 1, let only = remote.first, !mapping.values.contains(only) {
                mapping[unmatched.first!] = only
            }
        }
        var next = (known.compactMap { Int($0.speaker.dropFirst(idPrefix.count)) }.max() ?? 0) + 1
        return placed.map { word in
            TimedWord(text: word.text, speaker: resolve(word.label, &mapping, &next, idPrefix), start: word.start, end: word.end)
        }
    }

    private static func resolve(_ label: String, _ mapping: inout [String: String], _ next: inout Int, _ prefix: String) -> String {
        if let id = mapping[label] { return id }
        let id = "\(prefix)\(next)"; next += 1; mapping[label] = id
        return id
    }

    /// One window through the first provider that answers. A throttled
    /// provider is waited out only when no other provider has a key.
    private func transcribe(window regions: [ClosedRange<Double>], audio: CallAudio, known: [TimedWord],
                            budget: inout TimeInterval, label: String) async throws -> [TimedWord] {
        let clips = SpeakerLinker.anchorClips(known).sorted { $0.key < $1.key }
        var lastError: Error = TranscriptionError.network("no_provider")
        while true {
            var waits: [TimeInterval] = []
            for via in providers() {
                do {
                    return try await transcribe(window: regions, audio: audio, clips: clips, known: known, via: via)
                } catch TranscriptionError.rateLimitedTransient(let retryAfter) {
                    Log.meeting.info("\(label, privacy: .public): \(via.rawValue, privacy: .public) rate limited")
                    waits.append(retryAfter ?? 60); lastError = TranscriptionError.rateLimitedTransient(retryAfter: retryAfter)
                } catch let error as TranscriptionError where Self.tryNextProvider(error) {
                    Log.meeting.error("\(label, privacy: .public): \(via.rawValue, privacy: .public) failed: \(String(describing: error), privacy: .public)")
                    lastError = error
                } catch is DecodingError {
                    Log.meeting.error("\(label, privacy: .public): \(via.rawValue, privacy: .public) returned unreadable segments")
                    lastError = TranscriptionError.network("unreadable_segments")
                }
            }
            guard let wait = waits.min(), wait + 2 <= budget else { throw lastError }
            budget -= wait + 2
            Log.meeting.info("\(label, privacy: .public): waiting \(Int(wait + 2), privacy: .public)s for the rate limit")
            try await sleep(wait + 2)
        }
    }

    /// Native: reference clips go inside the audio and the labels the API
    /// gives them name the speakers. Gateway: reference clips go as separate
    /// audio parts and the model answers with the ids.
    private func transcribe(window regions: [ClosedRange<Double>], audio: CallAudio, clips: [(key: String, value: [ClosedRange<Double>])],
                            known: [TimedWord], via: ModelProvider) async throws -> [TimedWord] {
        var request = AssembledAudio()
        if via == .gemini {
            for (id, ranges) in clips { try request.appendAnchor(id: id, clips: ranges, from: audio) }
            try request.appendBody(regions, from: audio)
            let raw = try await client.transcribeSpeakers(audio: try FLACEncoder.encode(samples: request.samples),
                                                          model: models.transcribe, endpoint: endpoint, deadline: 600)
            return Self.place(raw, audio: request, call: audio, known: known, mapping: SpeakerLinker.link(words: raw, anchors: request.anchors))
        }
        try request.appendBody(regions, from: audio)
        var references: [(id: String, audio: Data)] = []
        for (id, ranges) in clips {
            var clip = AssembledAudio()
            try clip.appendBody(ranges, from: audio)
            references.append((id, try FLACEncoder.encode(samples: clip.samples)))
        }
        let raw = try await client.transcribeSpeakers(audio: try FLACEncoder.encode(samples: request.samples), references: references,
                                                      model: models.flash, deadline: 600, via: via)
        let ids = Set(clips.map(\.key))
        let mapping = Dictionary(uniqueKeysWithValues: ids.map { ($0, $0) })
        return Self.place(raw, audio: request, call: audio, known: known, mapping: mapping)
    }

    static func tryNextProvider(_ error: TranscriptionError) -> Bool {
        switch error {
        case .rateLimitedDaily, .modelUnavailable, .safetyBlocked, .badRequest, .network, .timeout, .auth: return true
        case .offline, .emptyTranscript, .rateLimitedTransient: return false
        }
    }
}
