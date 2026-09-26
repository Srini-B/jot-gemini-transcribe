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

/// Paid-tier Standard prices from ai.google.dev/gemini-api/docs/pricing,
/// USD per one million tokens, copied 2026-09-26. A free-tier key is billed
/// nothing; the app cannot tell which tier a key is on, so it always shows
/// the paid-tier figure and says so on the Cost pane.
///
/// Models are matched by prefix, longest first, so `gemini-3.5-transcribe-live`
/// wins over `gemini-3.5-transcribe` and a dated suffix (`-preview-09-2026`)
/// still resolves.
public struct ModelPrice: Equatable, Sendable {
    public var textIn: Double
    public var audioIn: Double
    public var imageIn: Double
    public var cachedIn: Double
    public var textOut: Double
    public var audioOut: Double

    public init(textIn: Double, audioIn: Double? = nil, imageIn: Double? = nil,
                cachedIn: Double = 0, textOut: Double, audioOut: Double? = nil) {
        self.textIn = textIn
        self.audioIn = audioIn ?? textIn
        self.imageIn = imageIn ?? textIn
        self.cachedIn = cachedIn
        self.textOut = textOut
        self.audioOut = audioOut ?? textOut
    }

    public func cost(_ usage: TokenUsage) -> Double {
        let perMillion = Double(usage.textIn) * textIn
            + Double(usage.audioIn) * audioIn
            + Double(usage.imageIn) * imageIn
            + Double(usage.cachedIn) * cachedIn
            + Double(usage.textOut + usage.thoughtOut) * textOut
            + Double(usage.audioOut) * audioOut
        return perMillion / 1_000_000
    }
}

public enum PriceBook {
    /// Gemini 3.8 Flash doubles on 2027-01-01 per the pricing page.
    static let flash38Increase = Calendar(identifier: .gregorian)
        .date(from: DateComponents(timeZone: TimeZone(identifier: "UTC"), year: 2027, month: 1, day: 1))!

    static func prices(at date: Date) -> [(prefix: String, price: ModelPrice)] {
        let late = date >= flash38Increase
        return [
            ("gemini-3.8-flash", late
                ? ModelPrice(textIn: 1.50, cachedIn: 0.15, textOut: 7.50)
                : ModelPrice(textIn: 0.75, cachedIn: 0.075, textOut: 3.75)),
            ("gemini-3.5-transcribe-live", ModelPrice(textIn: 3.50, audioIn: 3.50, textOut: 21.00)),
            ("gemini-3.5-transcribe", ModelPrice(textIn: 2.00, audioIn: 2.00, textOut: 12.00)),
            ("gemini-3.5-live-translate", ModelPrice(textIn: 3.50, audioIn: 3.50, textOut: 21.00, audioOut: 21.00)),
            ("gemini-3.1-flash-lite", ModelPrice(textIn: 0.25, audioIn: 0.50, cachedIn: 0.025, textOut: 1.50)),
            ("gemini-3-flash", ModelPrice(textIn: 0.50, audioIn: 1.00, cachedIn: 0.05, textOut: 3.00)),
            ("gemini-2.5-flash-lite", ModelPrice(textIn: 0.10, audioIn: 0.30, textOut: 0.40)),
            ("gemini-2.5-flash", ModelPrice(textIn: 0.30, audioIn: 1.00, cachedIn: 0.03, textOut: 2.50)),
        ]
    }

    /// Price for a model ID, or nil when the pricing page has no entry.
    public static func price(for model: String, at date: Date = Date()) -> ModelPrice? {
        let id = model.lowercased()
        return prices(at: date)
            .filter { id.hasPrefix($0.prefix) }
            .max { $0.prefix.count < $1.prefix.count }?
            .price
    }

    /// Cost in USD, or nil for a model with no price entry.
    public static func cost(model: String, usage: TokenUsage, at date: Date = Date()) -> Double? {
        price(for: model, at: date)?.cost(usage)
    }

    /// Audio tokens per second for estimation: the transcribe models bill 25,
    /// every other Gemini model 32 (both from the pricing page).
    public static func audioTokensPerSecond(model: String) -> Double {
        model.lowercased().contains("transcribe") ? 25 : 32
    }
}
