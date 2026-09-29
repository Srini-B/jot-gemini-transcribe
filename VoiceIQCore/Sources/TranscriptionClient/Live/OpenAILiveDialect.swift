import Foundation

/// OpenAI's realtime transcription session (`gpt-live-transcribe`), over
/// `WebSocketTransport.openAIEndpoint`.
///
/// Probed 2026-09-28 with a real key:
///  - The server sends `session.created`, then `session.updated` once our
///    configuration applies; the latter is the go-ahead.
///  - `audio/pcm` must be at least 24 kHz; 16 kHz is rejected with
///    `integer_below_min_value`. The app records 16 kHz, so frames are
///    resampled here.
///  - Turn detection must be off (`null`): the model does not support server
///    VAD, and the hotkey decides turns anyway. `input_audio_buffer.commit`
///    ends a turn; deltas stream while the user speaks and the turn's
///    `...transcription.completed` arrived 0.6–0.9 s after the commit.
public struct OpenAILiveDialect: LiveDialect {
    public let model: String
    public let delay: OpenAIConfig.LiveDelay
    public let keywords: [String]

    static let sampleRate = 24_000

    public init(model: String, delay: OpenAIConfig.LiveDelay, keywords: [String]) {
        self.model = model
        self.delay = delay
        self.keywords = GeminiClient.openAIKeywords(keywords)
    }

    public func setupFrame() -> Data? {
        var transcription: [String: Any] = ["model": model, "delay": delay.rawValue]
        if !keywords.isEmpty { transcription["keywords"] = keywords }
        return Self.json([
            "type": "session.update",
            "session": [
                "type": "transcription",
                "audio": ["input": [
                    "format": ["type": "audio/pcm", "rate": Self.sampleRate],
                    "transcription": transcription,
                    "turn_detection": NSNull(),
                ] as [String: Any]],
            ] as [String: Any],
        ])
    }

    public func audioFrame(_ pcm: Data) -> Data {
        Self.json(["type": "input_audio_buffer.append", "audio": Self.upsample16to24(pcm).base64EncodedString()])
    }

    public func activityStartFrame() -> Data? { nil }

    public func activityEndFrame() -> Data { Self.json(["type": "input_audio_buffer.commit"]) }

    public func decode(_ frame: Data) -> [LiveEvent] {
        guard let root = (try? JSONSerialization.jsonObject(with: frame)) as? [String: Any],
              let type = root["type"] as? String else { return [] }
        switch type {
        case "session.updated":
            return [.setupComplete]
        case "error":
            let error = root["error"] as? [String: Any]
            return [.failed(error?["message"] as? String ?? "unknown realtime error")]
        case "conversation.item.input_audio_transcription.delta":
            guard let delta = root["delta"] as? String, !delta.isEmpty else { return [] }
            return [.partialDelta(delta)]
        case "conversation.item.input_audio_transcription.completed":
            // An empty transcript is a finished, silent turn: `finish` turns
            // an all-empty result into `.silent` rather than waiting it out.
            return [.final((root["transcript"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines))]
        case "conversation.item.input_audio_transcription.failed":
            let error = root["error"] as? [String: Any]
            return [.failed(error?["message"] as? String ?? "transcription failed")]
        default:
            return []
        }
    }

    public func isGenerationComplete(_ frame: Data) -> Bool {
        guard let root = (try? JSONSerialization.jsonObject(with: frame)) as? [String: Any],
              let type = root["type"] as? String else { return false }
        return type == "conversation.item.input_audio_transcription.completed"
            || type == "conversation.item.input_audio_transcription.failed"
    }

    /// Each turn reports its own seconds; billing is by the audio sent, so
    /// the session total is computed from that instead of summing turns.
    public func reportedUsage(in frame: Data) -> TokenUsage? { nil }

    public func usage(reported: TokenUsage?, audioSeconds: Double, outputCharacters: Int) -> TokenUsage {
        TokenUsage.fromAudioMinutes(seconds: audioSeconds, model: model)
            ?? TokenUsage.estimated(audioSeconds: audioSeconds, outputCharacters: outputCharacters)
    }

    /// 16 kHz → 24 kHz mono Int16 by linear interpolation. Each frame is
    /// resampled on its own; the last output samples hold the frame's final
    /// input sample, a sub-sample error every 100 ms that speech recognition
    /// does not notice.
    static func upsample16to24(_ pcm: Data) -> Data {
        let count = pcm.count / 2
        guard count > 0 else { return Data() }
        let input: [Int16] = pcm.withUnsafeBytes { raw in
            (0..<count).map { Int16(littleEndian: raw.loadUnaligned(fromByteOffset: $0 * 2, as: Int16.self)) }
        }
        let outputCount = count * 3 / 2
        var output = [Int16](repeating: 0, count: outputCount)
        for index in 0..<outputCount {
            let position = Double(index) * 2 / 3
            let lower = Int(position)
            let upper = min(lower + 1, count - 1)
            let fraction = position - Double(lower)
            output[index] = Int16((Double(input[lower]) * (1 - fraction) + Double(input[upper]) * fraction).rounded())
        }
        return output.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    private static func json(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }
}
