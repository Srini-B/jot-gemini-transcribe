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

/// Who the Gemini calls go through. The models are the same either way; the
/// provider decides the endpoint, the auth header, and whose quota is spent.
///
/// The gateways exist for one reason: a Google AI Studio key on a low tier hits
/// per-minute and per-day limits that a long dictation cannot get past, and
/// raising the tier takes weeks of spend. OpenRouter and Vercel AI Gateway bill
/// per call with no tier gate.
public enum ModelProvider: String, CaseIterable, Sendable, Codable, Identifiable {
    case gemini
    case openRouter
    case vercel

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .gemini: return "Google AI Studio"
        case .openRouter: return "OpenRouter"
        case .vercel: return "Vercel AI Gateway"
        }
    }

    /// Where the pricing on the Cost pane comes from.
    public var pricingNote: String {
        switch self {
        case .gemini: return "Paid-tier Standard prices from the Gemini API pricing page. A free-tier key is billed nothing."
        case .openRouter: return "Costs reported by OpenRouter for each call."
        case .vercel: return "Costs reported by Vercel AI Gateway for each call."
        }
    }

    /// Which provider serves the next call.
    ///
    /// The user's choice wins when its key is present. Otherwise the first
    /// provider with a key (in declaration order) is used, so removing a key
    /// never strands the app on a provider it cannot reach. With no key the
    /// answer is Gemini, so every "add your key" path keeps pointing at the
    /// same place it always has.
    public static func resolve(preferred: ModelProvider, available: Set<ModelProvider>) -> ModelProvider {
        if available.contains(preferred) { return preferred }
        return allCases.first(where: available.contains) ?? .gemini
    }
}
