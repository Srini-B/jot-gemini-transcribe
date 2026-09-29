// Copyright 2026 Google LLC
// Licensed under the Apache License, Version 2.0.

import Foundation

/// ElevenLabs Scribe v2 Realtime, over `WebSocketTransport.elevenLabs`.
///
/// From the API reference and the official SDKs (read 2026-09-28; not yet
/// run against a real key):
///  - Everything is configured in the socket URL (`socketURL`); the client
///    sends no setup message. The server's `session_started` is the go-ahead.
///  - Audio goes as JSON text frames, `input_audio_chunk` with base64 PCM and
///    `commit: false`. A turn ends with an empty chunk and `commit: true`,
///    which the server answers with `committed_transcript`.
///  - `partial_transcript` carries the whole hypothesis for the open turn.
///  - In manual mode the server commits by itself after about 36 s of
///    uncommitted audio, and the docs advise committing every 20–30 s, so
///    turns roll at the first pause after 20 s and at 30 s regardless. That
///    keeps one committed transcript per turn the client closed.
///  - Errors arrive as `{"message_type": <kind>, "error": "..."}`.
public struct ElevenLabsLiveDialect: LiveDialect {
    public let model: String
    public let keyterms: [String]
    public let noVerbatim: Bool

    static let sampleRate = 16_000
    static let errorKinds: Set<String> = [
        "auth_error", "quota_exceeded", "transcriber_error", "input_error", "invalid_request", "error",
        "commit_throttled", "unaccepted_terms", "rate_limited", "queue_overflow", "resource_exhausted",
        "session_time_limit_exceeded", "chunk_size_exceeded", "insufficient_audio_activity",
    ]

    public init(model: String = ElevenLabs.realtimeModel, keyterms: [String], noVerbatim: Bool) {
        self.model = model
        self.keyterms = ElevenLabs.keyterms(keyterms, limit: ElevenLabs.realtimeKeytermLimit,
                                            maxCharacters: ElevenLabs.realtimeKeytermCharacters)
        self.noVerbatim = noVerbatim
    }

    /// Keyterms repeat as `keyterms=a&keyterms=b`, as the SDKs send them. `+`
    /// is escaped too, since servers read a bare one as a space.
    public var socketURL: URL {
        var items: [(String, String)] = [
            ("model_id", model), ("audio_format", "pcm_16000"), ("commit_strategy", "manual"),
        ]
        if noVerbatim { items.append(("no_verbatim", "true")) }
        items += keyterms.map { ("keyterms", $0) }
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=")
        let query = items.map { name, value in
            "\(name)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
        }.joined(separator: "&")
        return URL(string: "\(ElevenLabs.realtimeEndpoint.absoluteString)?\(query)")!
    }

    public var activityRoll: (roll: Int, hardLimit: Int) { (20, 30) }

    public func setupFrame() -> Data? { nil }

    public func audioFrame(_ pcm: Data) -> Data {
        Self.chunk(pcm.base64EncodedString(), commit: false)
    }

    public func activityStartFrame() -> Data? { nil }

    public func activityEndFrame() -> Data { Self.chunk("", commit: true) }

    public func decode(_ frame: Data) -> [LiveEvent] {
        guard let root = (try? JSONSerialization.jsonObject(with: frame)) as? [String: Any],
              let kind = root["message_type"] as? String else { return [] }
        switch kind {
        case "session_started":
            return [.setupComplete]
        case "partial_transcript":
            return [.partial(root["text"] as? String ?? "")]
        case "committed_transcript":
            return [.final((root["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines))]
        default:
            guard Self.errorKinds.contains(kind) else { return [] }
            return [.failed("\(kind): \(root["error"] as? String ?? "no detail")")]
        }
    }

    public func isGenerationComplete(_ frame: Data) -> Bool {
        guard let root = (try? JSONSerialization.jsonObject(with: frame)) as? [String: Any] else { return false }
        return root["message_type"] as? String == "committed_transcript"
    }

    public func reportedUsage(in frame: Data) -> TokenUsage? { nil }

    /// Billed per second of audio sent, at the list price.
    public func usage(reported: TokenUsage?, audioSeconds: Double, outputCharacters: Int) -> TokenUsage {
        TokenUsage.fromAudioMinutes(seconds: audioSeconds, model: model)
            ?? TokenUsage.estimated(audioSeconds: audioSeconds, outputCharacters: outputCharacters)
    }

    private static func chunk(_ base64: String, commit: Bool) -> Data {
        let object: [String: Any] = [
            "message_type": "input_audio_chunk", "audio_base_64": base64, "commit": commit, "sample_rate": sampleRate,
        ]
        return (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }
}
