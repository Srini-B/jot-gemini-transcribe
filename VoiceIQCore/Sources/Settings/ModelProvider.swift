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

/// Whose models run: Gemini's or OpenAI's. Settings calls this the provider.
public enum ModelProvider: String, CaseIterable, Sendable, Codable, Identifiable {
    case gemini
    case openAI

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .gemini: return "Gemini"
        case .openAI: return "OpenAI"
        }
    }

    /// The provider's own API, reached with its own key.
    public var directName: String {
        switch self {
        case .gemini: return "Google AI Studio"
        case .openAI: return "OpenAI API"
        }
    }

    /// Whether the writing model can take the recording as input. The Gemini
    /// flash model hears audio, which is what the one-call dictation, the
    /// audio-checked cleanup and gateway meeting transcription rely on. GPT-6
    /// Luna takes text and images only (and rejects FLAC even as
    /// `input_audio`, probed 2026-09-28).
    public var writingModelHearsAudio: Bool { self == .gemini }

    /// Usage records store only the model ID; the provider is read off it,
    /// with or without a gateway prefix (`google/…`, `openai/…`).
    public init?(modelID: String) {
        let id = modelID.lowercased()
        if Self.gemini.modelPrefixes.contains(where: id.hasPrefix) { self = .gemini }
        else if Self.openAI.modelPrefixes.contains(where: id.hasPrefix) { self = .openAI }
        else { return nil }
    }

    /// Model ID prefixes, for `init(modelID:)` and SQL `LIKE` filters.
    public var modelPrefixes: [String] {
        switch self {
        case .gemini: return ["gemini", "google/"]
        case .openAI: return ["gpt", "whisper", "openai/"]
        }
    }
}

/// How calls reach the provider: its own API, or a gateway. OpenRouter and
/// Vercel AI Gateway serve both providers' models with one key each, so a
/// gateway key is entered once whichever provider is selected.
///
/// The gateways exist for one reason: a Google AI Studio key on a low tier hits
/// per-minute and per-day limits that a long dictation cannot get past, and
/// raising the tier takes weeks of spend. Both bill per call with no tier gate.
public enum ModelGateway: String, CaseIterable, Sendable, Codable, Identifiable {
    case direct
    case openRouter
    case vercel

    public var id: String { rawValue }

    public func displayName(for provider: ModelProvider) -> String {
        switch self {
        case .direct: return provider.directName
        case .openRouter: return "OpenRouter"
        case .vercel: return "Vercel AI Gateway"
        }
    }
}

/// The host a call is sent to. Derived from a route: the transport, auth
/// header and response envelopes differ per endpoint, not per provider.
public enum ModelEndpoint: String, Sendable {
    case gemini
    case openAI
    case openRouter
    case vercel

    /// Who receives the request, for privacy copy.
    public var hostName: String {
        switch self {
        case .gemini: return "Google"
        case .openAI: return "OpenAI"
        case .openRouter: return "OpenRouter"
        case .vercel: return "Vercel"
        }
    }
}

/// One way to run the app's model calls: a provider's models over a gateway.
public struct ModelRoute: Hashable, Sendable {
    public var provider: ModelProvider
    public var gateway: ModelGateway

    public init(provider: ModelProvider, gateway: ModelGateway) {
        self.provider = provider
        self.gateway = gateway
    }

    public var endpoint: ModelEndpoint {
        switch gateway {
        case .direct: return provider == .gemini ? .gemini : .openAI
        case .openRouter: return .openRouter
        case .vercel: return .vercel
        }
    }

    /// Streaming transcription runs only on the providers' own sockets.
    /// OpenRouter has no streaming transcription; Vercel's beta WebSocket
    /// protocol is not implemented.
    public var supportsLiveTranscription: Bool { gateway == .direct }

    /// For logs.
    public var label: String { "\(provider.rawValue)/\(gateway.rawValue)" }

    /// Where the pricing on the Cost pane comes from.
    public var pricingNote: String {
        switch (provider, gateway) {
        case (.gemini, .direct): return "Paid-tier Standard prices from the Gemini API pricing page. A free-tier key is billed nothing."
        case (.openAI, .direct): return "Standard prices from the OpenAI API pricing page."
        case (_, .openRouter): return "Costs reported by OpenRouter for each call."
        case (_, .vercel): return "Costs reported by Vercel AI Gateway for each call."
        }
    }

    /// Which route serves the next call. The provider is always the one
    /// selected. The chosen gateway wins when its key is present; otherwise
    /// the first gateway with a key (direct, OpenRouter, Vercel), so removing
    /// a key never strands the app. With no key the answer is direct, so
    /// every "add your key" path points at the provider's own key.
    public static func resolve(provider: ModelProvider, preferred: ModelGateway,
                               available: Set<ModelGateway>) -> ModelRoute {
        let gateway = available.contains(preferred)
            ? preferred
            : ModelGateway.allCases.first(where: available.contains) ?? .direct
        return ModelRoute(provider: provider, gateway: gateway)
    }

    /// Whether this route can make a speaker-labelled meeting transcript.
    /// Gemini can on every route (the flash model labels speakers through a
    /// gateway); OpenAI only on its own API, because no gateway serves
    /// `gpt-4o-transcribe-diarize` and Luna cannot hear audio.
    public var supportsMeetings: Bool { provider == .gemini || gateway == .direct }

    /// Routes a meeting is transcribed on, in order: the selected provider's
    /// meeting-capable routes (chosen gateway first), then the other
    /// provider's. OpenAI over a gateway therefore uses the OpenAI key when
    /// there is one, and otherwise Gemini. Empty when no stored key can do it.
    public static func meetingOrder(provider: ModelProvider, preferred: ModelGateway,
                                    available: (ModelProvider) -> Set<ModelGateway>) -> [ModelRoute] {
        let other: ModelProvider = provider == .gemini ? .openAI : .gemini
        return [provider, other].flatMap { candidate -> [ModelRoute] in
            let keys = available(candidate)
            return fallbackOrder(provider: candidate, preferred: preferred, available: keys)
                .filter { keys.contains($0.gateway) && $0.supportsMeetings }
        }
    }

    /// For the meeting failure message.
    public var displayName: String {
        gateway == .direct ? provider.directName : "\(provider.displayName) via \(gateway.displayName(for: provider))"
    }

    /// The resolved route, then the same provider over every other gateway
    /// with a key. A long meeting moves on when a gateway throttles or refuses.
    public static func fallbackOrder(provider: ModelProvider, preferred: ModelGateway,
                                     available: Set<ModelGateway>) -> [ModelRoute] {
        let first = resolve(provider: provider, preferred: preferred, available: available)
        return [first] + ModelGateway.allCases
            .filter { $0 != first.gateway && available.contains($0) }
            .map { ModelRoute(provider: provider, gateway: $0) }
    }
}
