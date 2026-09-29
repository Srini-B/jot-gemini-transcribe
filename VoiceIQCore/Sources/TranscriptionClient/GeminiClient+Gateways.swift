import Foundation

/// Either provider's models through the OpenAI-shaped gateways: OpenRouter and
/// Vercel AI Gateway. Gemini models are `google/<id>`, OpenAI's `openai/<id>`.
///
/// Two calls carry everything the app does:
///  - a transcription endpoint for the transcribe model. No smart mode, custom
///    vocabulary or diarization there, so the cleanup pass does the formatting
///    work the Gemini interactions endpoint would have done.
///  - `POST /chat/completions` for every flash call, with text, JPEG and FLAC
///    as message content parts.
///
/// Live (WebSocket) transcription has no gateway equivalent, so the
/// coordinator skips the live session whenever a gateway is active.
/// Extra message content after the prompt, in order.
public enum ChatPart: Sendable {
    case text(String)
    case flac(Data)
}

extension GeminiClient {
    static let openRouterEndpoint = URL(string: "https://openrouter.ai/api/v1")!
    static let vercelEndpoint = URL(string: "https://ai-gateway.vercel.sh/v1")!
    /// Vercel's speech-to-text is a separate, versioned protocol rather than
    /// the OpenAI `/audio/transcriptions` shape.
    static let vercelTranscriptionEndpoint = URL(string: "https://ai-gateway.vercel.sh/v4/ai")!
    static let vercelTranscriptionHeaders = [
        "ai-gateway-protocol-version": "0.0.1",
        "ai-transcription-model-specification-version": "4",
    ]

    /// Both gateways name Google models `google/<gemini id>`; the live model
    /// maps to its batch sibling because there is no live surface here.
    static func gatewayModelID(_ model: String) -> String {
        if model.contains("/") { return model }
        var id = model
        if id.hasSuffix("-live") { id.removeLast("-live".count) }
        return "google/\(id)"
    }

    /// OpenRouter slugs of Google's priority-tier endpoints.
    static let openRouterPriorityEndpoints = ["google-ai-studio/priority", "google-vertex/global/priority"]

    /// The gateway ID of the transcription model for the route's provider.
    /// `geminiModel` is what the caller passed; OpenAI's comes from `OpenAIConfig`.
    func transcriptionModelID(_ geminiModel: String, route: ModelRoute) -> String {
        route.provider == .gemini ? Self.gatewayModelID(geminiModel) : Self.openAIGatewayID(openAIConfig().transcribeModel)
    }

    func writingModelID(_ geminiModel: String, route: ModelRoute) -> String {
        route.provider == .gemini ? Self.gatewayModelID(geminiModel) : Self.openAIGatewayID(openAIConfig().writingModel)
    }

    static func openAIGatewayID(_ model: String) -> String {
        model.contains("/") ? model : "openai/\(model)"
    }

    static func gatewayEndpoint(_ via: ModelEndpoint) -> URL {
        via == .vercel ? vercelEndpoint : openRouterEndpoint
    }

    func gatewayTranscribe(audio: Data, mimeType: String = "audio/flac", model: String,
                           deadline: TimeInterval, stage: UsageStage, via: ModelEndpoint) async throws -> String {
        let modelID = Self.gatewayModelID(model)
        if via == .vercel {
            let body: [String: Any] = ["audio": audio.base64EncodedString(), "mediaType": mimeType]
            let data = try await post(
                path: "transcription-model",
                body: try JSONSerialization.data(withJSONObject: body),
                endpoint: Self.vercelTranscriptionEndpoint, deadline: deadline, modelLabel: modelID,
                stage: stage, via: .vercel,
                extraHeaders: Self.vercelTranscriptionHeaders.merging(["ai-model-id": modelID]) { $1 }
            )
            return try Self.extractGatewayTranscript(from: data)
        }
        let body: [String: Any] = [
            "model": modelID,
            "input_audio": ["data": audio.base64EncodedString(), "format": Self.audioFormat(mimeType)],
        ]
        let data = try await post(
            path: "audio/transcriptions",
            body: try JSONSerialization.data(withJSONObject: body),
            endpoint: Self.openRouterEndpoint, deadline: deadline, modelLabel: modelID,
            stage: stage, via: .openRouter
        )
        return try Self.extractGatewayTranscript(from: data)
    }

    func gatewayChat(prompt: String, images: [Data] = [], audioFLAC: Data? = nil, model: String,
                     provider: ModelProvider = .gemini,
                     deadline: TimeInterval, stage: UsageStage, jsonObject: Bool = false,
                     jsonSchema: [String: Any]? = nil, parts: [ChatPart] = [], via: ModelEndpoint) async throws -> String {
        let modelID = Self.gatewayModelID(model)
        var content: [[String: Any]] = [["type": "text", "text": prompt]]
        for part in parts {
            switch part {
            case let .text(text): content.append(["type": "text", "text": text])
            case let .flac(data): content.append(Self.audioPart(flac: data, via: via))
            }
        }
        content.append(contentsOf: images.map {
            ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\($0.base64EncodedString())"]]
        })
        if let audioFLAC {
            content.append(Self.audioPart(flac: audioFLAC, via: via))
        }
        // OpenAI models get the same message layout as on OpenAI's own API.
        let messages: [[String: Any]] = provider == .openAI && parts.isEmpty && audioFLAC == nil
            ? Self.openAIMessages(prompt: prompt, images: images, instructionRole: "system")
            : [["role": "user", "content": content]]
        var body: [String: Any] = [
            "model": modelID,
            "messages": messages,
            // Same knob as thinkingLevel "low" on the native API; OpenAI's
            // writing model runs without reasoning (see openAIReasoningEffort).
            "reasoning": ["effort": provider == .gemini ? "low" : Self.openAIReasoningEffort],
        ]
        // GPT-6 Luna accepts only the default temperature (probed 2026-09-28).
        if provider == .gemini { body["temperature"] = 0 }
        if via == .openRouter {
            // OpenRouter load-balances by price by default. A dictation waits on
            // this call, so ask for the fastest endpoint of the same model.
            // Google's endpoints come in flex (half price, measured 15–64 s),
            // standard, and priority (1.8× standard) tiers; priority is never
            // used. Measured 2026-09-28: this routes to Google AI Studio's
            // standard tier at the standard price, 1.8–2.4 s against 2.7–3.5 s.
            // https://openrouter.ai/docs/features/provider-routing
            body["provider"] = ["sort": "latency", "ignore": Self.openRouterPriorityEndpoints]
        }
        if let jsonSchema {
            body["response_format"] = ["type": "json_schema",
                                       "json_schema": ["name": "result", "strict": true, "schema": jsonSchema] as [String: Any]]
        } else if jsonObject {
            body["response_format"] = Self.jsonResponseFormat(via: via)
        }
        let data = try await post(
            path: "chat/completions",
            body: try JSONSerialization.data(withJSONObject: body),
            endpoint: Self.gatewayEndpoint(via), deadline: deadline, modelLabel: modelID,
            stage: stage, via: via
        )
        return try Self.extractGatewayMessage(from: data)
    }

    /// OpenRouter takes OpenAI's `input_audio` part; Vercel rejects it and
    /// wants the generic `file` part with a data URL (docs, 2026-09).
    static func audioPart(flac: Data, via: ModelEndpoint) -> [String: Any] {
        let base64 = flac.base64EncodedString()
        if via == .vercel {
            return ["type": "file", "file": ["filename": "audio.flac", "file_data": "data:audio/flac;base64,\(base64)"]]
        }
        return ["type": "input_audio", "input_audio": ["data": base64, "format": "flac"]]
    }

    /// Vercel documents `json` (legacy) and `json_schema`; `json_object` also
    /// worked when probed (2026-09-27), but the documented one is safer.
    static func jsonResponseFormat(via: ModelEndpoint) -> [String: Any] {
        ["type": via == .vercel ? "json" : "json_object"]
    }

    /// `GET /key` answers 200 for a usable key and 401 for a bad one.
    public func validateOpenRouterKey() async -> KeyCheck {
        var request = URLRequest(url: Self.openRouterEndpoint.appendingPathComponent("key"))
        request.timeoutInterval = 10
        applyAuth(&request, via: .openRouter)
        return await Self.keyCheck(session: session, request: request)
    }

    /// `GET /models` answers 200 for a usable key and 401 for a bad one.
    public func validateVercelKey() async -> KeyCheck {
        var request = URLRequest(url: Self.vercelEndpoint.appendingPathComponent("models"))
        request.timeoutInterval = 10
        applyAuth(&request, via: .vercel)
        return await Self.keyCheck(session: session, request: request)
    }

    private static func keyCheck(session: URLSession, request: URLRequest) async -> KeyCheck {
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else {
            return .unreachable
        }
        switch http.statusCode {
        case 200: return .valid
        case 500...599: return .unreachable
        default: return .rejected(errorMessage(from: data))
        }
    }

    // MARK: - Parsing

    static func audioFormat(_ mimeType: String) -> String {
        switch mimeType {
        case "audio/wav", "audio/x-wav": return "wav"
        case "audio/mp3", "audio/mpeg": return "mp3"
        case "audio/ogg": return "ogg"
        default: return "flac"
        }
    }

    /// `{"text": "...", ...}` from either gateway. A silent clip is an empty
    /// string, never an error, matching the Gemini extractors.
    static func extractGatewayTranscript(from data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TranscriptionError.network("unparseable_response")
        }
        let text = json["text"] as? String ?? ""
        if text.isEmpty {
            Log.transcription.info("gateway transcript empty; response keys: \(json.keys.sorted().joined(separator: ","), privacy: .public)")
        }
        return text
    }

    /// `choices[0].message.content`, which may be a string or an array of text
    /// parts. A `finish_reason` of `content_filter` is the safety block.
    static func extractGatewayMessage(from data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TranscriptionError.network("unparseable_response")
        }
        guard let choices = json["choices"] as? [[String: Any]], let first = choices.first else {
            throw TranscriptionError.network("no_choices")
        }
        if let finish = first["finish_reason"] as? String, finish == "content_filter" {
            throw TranscriptionError.safetyBlocked
        }
        let message = first["message"] as? [String: Any] ?? [:]
        let parts = message["content"] as? [[String: Any]] ?? []
        let text = message["content"] as? String ?? parts.compactMap { $0["text"] as? String }.joined()
        if text.isEmpty {
            // Shape only, never content: which keys came back and why it stopped.
            let details = (json["usage"] as? [String: Any])?["completion_tokens_details"] as? [String: Any] ?? [:]
            Log.transcription.error("gateway message empty: finish=\(first["finish_reason"] as? String ?? "nil", privacy: .public) message keys=\(message.keys.sorted().joined(separator: ","), privacy: .public) content type=\(String(describing: type(of: message["content"] as Any)), privacy: .public) reasoning tokens=\((details["reasoning_tokens"] as? NSNumber)?.intValue ?? -1, privacy: .public)")
        }
        return text
    }
}
