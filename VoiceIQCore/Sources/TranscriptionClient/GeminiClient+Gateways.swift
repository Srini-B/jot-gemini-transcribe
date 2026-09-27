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

/// The same Gemini models through the OpenAI-shaped gateways: OpenRouter and
/// Vercel AI Gateway.
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

    static func gatewayEndpoint(_ via: ModelProvider) -> URL {
        via == .vercel ? vercelEndpoint : openRouterEndpoint
    }

    func gatewayTranscribe(audio: Data, mimeType: String = "audio/flac", model: String,
                           deadline: TimeInterval, stage: UsageStage, via: ModelProvider) async throws -> String {
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
                     deadline: TimeInterval, stage: UsageStage, jsonObject: Bool = false,
                     via: ModelProvider) async throws -> String {
        let modelID = Self.gatewayModelID(model)
        var content: [[String: Any]] = [["type": "text", "text": prompt]]
        content.append(contentsOf: images.map {
            ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\($0.base64EncodedString())"]]
        })
        if let audioFLAC {
            content.append(Self.audioPart(flac: audioFLAC, via: via))
        }
        var body: [String: Any] = [
            "model": modelID,
            "messages": [["role": "user", "content": content]],
            "temperature": 0,
            // Same knob as thinkingLevel "low" on the native API.
            "reasoning": ["effort": "low"],
        ]
        if jsonObject { body["response_format"] = Self.jsonResponseFormat(via: via) }
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
    static func audioPart(flac: Data, via: ModelProvider) -> [String: Any] {
        let base64 = flac.base64EncodedString()
        if via == .vercel {
            return ["type": "file", "file": ["filename": "audio.flac", "file_data": "data:audio/flac;base64,\(base64)"]]
        }
        return ["type": "input_audio", "input_audio": ["data": base64, "format": "flac"]]
    }

    /// Vercel documents `json` (legacy) and `json_schema`; `json_object` also
    /// worked when probed (2026-09-27), but the documented one is safer.
    static func jsonResponseFormat(via: ModelProvider) -> [String: Any] {
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
        return json["text"] as? String ?? ""
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
        if let text = message["content"] as? String { return text }
        let parts = message["content"] as? [[String: Any]] ?? []
        return parts.compactMap { $0["text"] as? String }.joined()
    }
}
