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

/// What the server said. Deliberately small: everything the Live API sends that
/// VoiceiQ does not act on becomes `nil` rather than a case, so an API that grows new
/// message types does not start throwing in the middle of someone's dictation.
public enum LiveEvent: Equatable, Sendable {
    /// The credential was accepted and the session is configured. Audio sent
    /// before this arrives is buffered, not lost.
    case setupComplete
    /// A speculative hypothesis, replaced by later ones. **Display only.**
    /// This must never reach the cursor, History, or `rawTranscript`.
    case partial(String)
    /// More text for the open turn's hypothesis (OpenAI sends deltas, not the
    /// whole hypothesis). Display only, like `partial`.
    case partialDelta(String)
    /// Authoritative text for a finished speech segment. In SMART mode this is
    /// already cleaned and formatted.
    case final(String)
    /// The server is closing the session — the 10-minute cap, or its own reasons.
    case goAway
    /// An error envelope. Terminal for the session.
    case failed(String)
}

/// Everything that varies per session.
public struct LiveSetup: Equatable, Sendable {
    public var model: String
    public var smart: Bool
    public var customVocabulary: [String]

    public init(model: String = "gemini-3.5-transcribe-live",
                smart: Bool = true,
                customVocabulary: [String] = []) {
        self.model = model
        self.smart = smart
        self.customVocabulary = customVocabulary
    }
}

/// The wire format of one streaming transcription API. `LiveTranscriptionSession`
/// owns the ring, the send order, turn rollover and the finish rules; a dialect
/// only builds and reads frames, so every one of them is testable without a
/// socket.
public protocol LiveDialect: Sendable {
    /// For usage records.
    var model: String { get }
    func setupFrame() -> Data
    /// `pcm` is the app's 16 kHz mono Int16; a dialect resamples if its API
    /// needs another rate.
    func audioFrame(_ pcm: Data) -> Data
    /// Nil when the API opens the next turn by itself.
    func activityStartFrame() -> Data?
    func activityEndFrame() -> Data
    func decode(_ frame: Data) -> [LiveEvent]
    /// True for the frame that closes a turn the client ended.
    func isGenerationComplete(_ frame: Data) -> Bool
    /// Usage the server reported in this frame, if any.
    func reportedUsage(in frame: Data) -> TokenUsage?
    /// What the session cost, from the largest reported usage or, without
    /// one, the audio sent and text received.
    func usage(reported: TokenUsage?, audioSeconds: Double, outputCharacters: Int) -> TokenUsage
}

/// Gemini's Live API, through the `LiveProtocol` frames below.
public struct GeminiLiveDialect: LiveDialect {
    public let setup: LiveSetup
    public init(setup: LiveSetup) { self.setup = setup }

    public var model: String { setup.model }
    public func setupFrame() -> Data { LiveProtocol.setupFrame(setup) }
    public func audioFrame(_ pcm: Data) -> Data { LiveProtocol.audioFrame(pcm) }
    public func activityStartFrame() -> Data? { LiveProtocol.activityStartFrame() }
    public func activityEndFrame() -> Data { LiveProtocol.activityEndFrame() }
    public func decode(_ frame: Data) -> [LiveEvent] { LiveProtocol.decodeAll(frame) }
    public func isGenerationComplete(_ frame: Data) -> Bool { LiveProtocol.isGenerationComplete(frame) }
    public func reportedUsage(in frame: Data) -> TokenUsage? { TokenUsage.fromLiveFrame(frame) }
    public func usage(reported: TokenUsage?, audioSeconds: Double, outputCharacters: Int) -> TokenUsage {
        reported ?? TokenUsage.estimated(audioSeconds: audioSeconds, outputCharacters: outputCharacters,
                                         audioTokensPerSecond: PriceBook.audioTokensPerSecond(model: model))
    }
}

/// Frame construction and decoding for the Live API WebSocket, as pure functions
/// over `Data` so every one of them is testable without a socket.
public enum LiveProtocol {

    public static let audioMIME = "audio/pcm;rate=16000"

    /// The ONLY place a live setup frame is constructed.
    ///
    /// **NEVER add `languageCodes` here without probing it first.** On the
    /// interactions endpoint, sending `language_codes` alongside `mode: smart`
    /// returns VERBATIM output with HTTP 200, no error, and no runtime signal of
    /// any kind — the formatting silently stops happening and nothing anywhere
    /// says so. The live API takes both fields in the same object, and the
    /// published example pairs them, which is precisely how that bug would ship
    /// a second time. Omitting the field is also what the docs prescribe for
    /// automatic language detection, so there is no cost to leaving it out.
    ///
    /// Manual VAD is not optional here: VoiceiQ decides turn boundaries from the
    /// hotkey, so server-side voice detection would cut turns in the middle of
    /// someone pausing to think.
    public static func setupFrame(_ setup: LiveSetup) -> Data {
        var transcription: [String: Any] = ["mode": setup.smart ? "SMART" : "VERBATIM"]
        if !setup.customVocabulary.isEmpty {
            transcription["customVocabulary"] = setup.customVocabulary
        }
        let frame: [String: Any] = [
            "setup": [
                "model": "models/\(setup.model)",
                "generationConfig": ["responseModalities": ["TEXT"]],
                "inputAudioTranscription": transcription,
                "realtimeInputConfig": [
                    "automaticActivityDetection": ["disabled": true],
                ],
            ],
        ]
        return (try? JSONSerialization.data(withJSONObject: frame)) ?? Data()
    }

    public static func audioFrame(_ pcm: Data) -> Data {
        let frame: [String: Any] = [
            "realtimeInput": [
                "audio": ["data": pcm.base64EncodedString(), "mimeType": audioMIME],
            ],
        ]
        return (try? JSONSerialization.data(withJSONObject: frame)) ?? Data()
    }

    public static func activityStartFrame() -> Data {
        (try? JSONSerialization.data(withJSONObject: ["realtimeInput": ["activityStart": [:] as [String: Any]]])) ?? Data()
    }

    public static func activityEndFrame() -> Data {
        (try? JSONSerialization.data(withJSONObject: ["realtimeInput": ["activityEnd": [:] as [String: Any]]])) ?? Data()
    }

    /// Decodes one server frame.
    ///
    /// Returns nil for anything unrecognised. That is deliberate: an unknown
    /// message is not a reason to tear down a session that is otherwise
    /// transcribing someone's sentence, and the fallback to the batch path is
    /// reserved for failures that actually cost words.
    ///
    /// The first event in the frame; see `decodeAll`.
    public static func decode(_ data: Data) -> LiveEvent? {
        decodeAll(data).first
    }

    /// Decodes every event in one server frame.
    ///
    /// A frame can carry both a final (`inputTranscription`) for the turn that
    /// just closed and an interim for the one that opened. Both matter: the
    /// final is text that reaches the cursor, the interim is what the pill
    /// shows. The final comes first so the two are never confused, and an
    /// interim is never returned as a final.
    public static func decodeAll(_ data: Data) -> [LiveEvent] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return []
        }
        if root["setupComplete"] != nil || root["setup_complete"] != nil {
            return [.setupComplete]
        }
        if let error = root["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "unknown live error"
            return [.failed(message)]
        }
        let content = (root["serverContent"] ?? root["server_content"]) as? [String: Any]
        if let content {
            if content["goAway"] != nil || content["go_away"] != nil { return [.goAway] }
            var events: [LiveEvent] = []
            if let text = transcriptText(content, "inputTranscription", "input_transcription") {
                events.append(.final(text))
            }
            if let text = transcriptText(content, "interimInputTranscription", "interim_input_transcription") {
                events.append(.partial(text))
            }
            return events
        }
        if root["goAway"] != nil || root["go_away"] != nil { return [.goAway] }
        return []
    }

    /// True for the frame the server sends once it has finished transcribing a
    /// closed turn. It follows the turn's final, in its own frame.
    public static func isGenerationComplete(_ data: Data) -> Bool {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let content = (root["serverContent"] ?? root["server_content"]) as? [String: Any]
        else { return false }
        return (content["generationComplete"] ?? content["generation_complete"]) as? Bool == true
    }

    /// Accepts both camelCase and snake_case because the two documented clients
    /// disagree about which the socket speaks, and guessing wrong here would look
    /// exactly like a model that transcribes nothing.
    private static func transcriptText(_ content: [String: Any], _ camel: String, _ snake: String) -> String? {
        guard let node = (content[camel] ?? content[snake]) as? [String: Any],
              let text = node["text"] as? String,
              !text.isEmpty
        else { return nil }
        return text
    }
}
