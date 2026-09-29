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

public extension Notification.Name {
    /// Posted after any SettingsStore write and after Keychain API-key writes,
    /// with `object` = the key ("showIdleIndicator", "apiKey", …). Runtime
    /// surfaces that render a setting (pill, status line, hotkey engine) observe
    /// this so toggles take effect the moment they're flipped — never "on the
    /// next unrelated transition".
    static let gtSettingDidChange = Notification.Name("io.blue.voiceiq.setting-changed")
}

/// UserDefaults-backed settings (M3 minimal; the Settings UI lands at M7).
/// Endpoint + model IDs are overridable because preview models get renamed.
public struct SettingsStore: Sendable {
    private static let defaults = UserDefaults.standard

    public init() {}

    private static func set(_ value: Any?, forKey key: String) {
        defaults.set(value, forKey: key)
        NotificationCenter.default.post(name: .gtSettingDidChange, object: key)
    }

    /// Single source of truth for endpoint-override validity — the Settings UI
    /// warning and the effective config MUST use the same predicate, or one of
    /// them lies about which endpoint is in use.
    public static func usableEndpointURL(_ raw: String?) -> URL? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
              let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            return nil
        }
        return url
    }

    /// True once the user finished onboarding — a deliberate "I'll add it later"
    /// must not re-trap them in the wizard every launch.
    public var hasCompletedOnboarding: Bool {
        Self.defaults.bool(forKey: "hasCompletedOnboarding")
    }

    public func setHasCompletedOnboarding(_ done: Bool) {
        Self.set(done, forKey: "hasCompletedOnboarding")
    }

    public var geminiConfig: GeminiConfig {
        var config = GeminiConfig()
        if let url = Self.usableEndpointURL(Self.defaults.string(forKey: "endpointOverride")) {
            config.endpoint = url
        }
        if let model = Self.defaults.string(forKey: "transcribeModelOverride"), !model.isEmpty {
            config.transcribeModel = model
        }
        if let model = Self.defaults.string(forKey: "liveModelOverride"), !model.isEmpty {
            config.liveModel = model
        }
        if let model = Self.defaults.string(forKey: "cleanupModelOverride"), !model.isEmpty {
            config.cleanupModel = model
        }
        return config
    }

    /// OpenAI's models, used only while OpenAI is the active provider.
    public var openAIConfig: OpenAIConfig {
        var config = OpenAIConfig()
        if let model = Self.nonEmpty("openAITranscribeModelOverride") { config.transcribeModel = model }
        if let model = Self.nonEmpty("openAILiveModelOverride") { config.liveModel = model }
        if let model = Self.nonEmpty("openAIWritingModelOverride") { config.writingModel = model }
        if let raw = Self.defaults.string(forKey: "openAILiveDelay"), let delay = OpenAIConfig.LiveDelay(rawValue: raw) {
            config.liveDelay = delay
        }
        return config
    }

    public var openAITranscribeModelOverride: String? { Self.defaults.string(forKey: "openAITranscribeModelOverride") }
    public var openAILiveModelOverride: String? { Self.defaults.string(forKey: "openAILiveModelOverride") }
    public var openAIWritingModelOverride: String? { Self.defaults.string(forKey: "openAIWritingModelOverride") }

    public func setOpenAITranscribeModelOverride(_ raw: String?) { Self.set(raw, forKey: "openAITranscribeModelOverride") }
    public func setOpenAILiveModelOverride(_ raw: String?) { Self.set(raw, forKey: "openAILiveModelOverride") }
    public func setOpenAIWritingModelOverride(_ raw: String?) { Self.set(raw, forKey: "openAIWritingModelOverride") }
    public func setOpenAILiveDelay(_ delay: OpenAIConfig.LiveDelay) { Self.set(delay.rawValue, forKey: "openAILiveDelay") }

    private static func nonEmpty(_ key: String) -> String? {
        guard let value = defaults.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    /// Gemini or OpenAI, chosen in Settings → Advanced. Before 2026-09-28
    /// `modelProvider` also held `openRouter` or `vercel`; those were Gemini
    /// over a gateway, so they read as Gemini here and as the gateway below.
    public var preferredProvider: ModelProvider {
        ModelProvider(rawValue: Self.defaults.string(forKey: "modelProvider") ?? "") ?? .gemini
    }

    /// The gateway chosen in Settings. Only matters when its key exists.
    public var preferredGateway: ModelGateway {
        if let raw = Self.defaults.string(forKey: "modelGateway"), let gateway = ModelGateway(rawValue: raw) { return gateway }
        return ModelGateway(rawValue: Self.defaults.string(forKey: "modelProvider") ?? "") ?? .direct
    }

    public func setPreferredProvider(_ provider: ModelProvider) {
        // Pin the gateway first: a legacy `modelProvider` gateway value is
        // about to be overwritten.
        Self.defaults.set(preferredGateway.rawValue, forKey: "modelGateway")
        Self.set(provider.rawValue, forKey: "modelProvider")
    }

    public func setPreferredGateway(_ gateway: ModelGateway) {
        Self.set(gateway.rawValue, forKey: "modelGateway")
    }

    /// Speech-to-text chosen in Settings. Only matters when its key exists.
    public var preferredTranscriptionSource: TranscriptionSource {
        TranscriptionSource(rawValue: Self.defaults.string(forKey: "transcriptionSource") ?? "") ?? .provider
    }

    public func setPreferredTranscriptionSource(_ source: TranscriptionSource) {
        Self.set(source.rawValue, forKey: "transcriptionSource")
    }

    /// Who transcribes the next dictation. ElevenLabs only while its key is
    /// stored, so removing the key falls back to the provider's own model.
    public var transcriptionSource: TranscriptionSource {
        preferredTranscriptionSource == .elevenLabs && KeychainStore.loadElevenLabsKey() != nil ? .elevenLabs : .provider
    }

    /// The route that serves calls right now; see `ModelRoute.resolve`.
    public var activeRoute: ModelRoute {
        let provider = preferredProvider
        return ModelRoute.resolve(provider: provider, preferred: preferredGateway,
                                  available: KeychainStore.gatewaysWithKeys(for: provider))
    }

    /// Routes for meeting transcription and notes; see `ModelRoute.meetingOrder`.
    public var meetingRoutes: [ModelRoute] {
        ModelRoute.meetingOrder(provider: preferredProvider, preferred: preferredGateway,
                                available: KeychainStore.gatewaysWithKeys(for:))
    }

    /// The active route, then the selected provider over each other gateway
    /// with a key. Never the other provider.
    public var fallbackRoutes: [ModelRoute] {
        let provider = preferredProvider
        return ModelRoute.fallbackOrder(provider: provider, preferred: preferredGateway,
                                        available: KeychainStore.gatewaysWithKeys(for: provider))
    }

    /// Show the resting dot at the bottom of the screen when idle. Off = the pill
    /// only appears while dictating.
    public var showIdleIndicator: Bool {
        Self.defaults.object(forKey: "showIdleIndicator") as? Bool ?? true
    }

    public func setShowIdleIndicator(_ show: Bool) {
        Self.set(show, forKey: "showIdleIndicator")
    }

    public var soundsEnabled: Bool {
        Self.defaults.object(forKey: "soundsEnabled") as? Bool ?? true
    }

    public func setSoundsEnabled(_ enabled: Bool) {
        Self.set(enabled, forKey: "soundsEnabled")
    }

    public var translationTargetLanguage: String {
        Self.defaults.string(forKey: "translationTargetLanguage") ?? "English"
    }

    public func setTranslationTargetLanguage(_ language: String) {
        let trimmed = language.trimmingCharacters(in: .whitespacesAndNewlines)
        Self.set(trimmed.isEmpty ? "English" : trimmed, forKey: "translationTargetLanguage")
    }

    /// Where the pill sits along the bottom of the screen, as a fraction of the
    /// visible width: 0 far left, 0.5 centre, 1 far right. Snapped to five
    /// stops so a drag ends somewhere predictable.
    public static let pillAnchors: [Double] = [0, 0.25, 0.5, 0.75, 1]

    public var pillAnchor: Double {
        Self.defaults.object(forKey: "pillAnchor") as? Double ?? 0.5
    }

    public func setPillAnchor(_ fraction: Double) {
        let nearest = Self.pillAnchors.min(by: { abs($0 - fraction) < abs($1 - fraction) }) ?? 0.5
        Self.set(nearest, forKey: "pillAnchor")
    }

    public var muteOtherAudioWhileDictating: Bool {
        Self.defaults.object(forKey: "muteOtherAudioWhileDictating") as? Bool ?? true
    }

    public func setMuteOtherAudioWhileDictating(_ enabled: Bool) {
        Self.set(enabled, forKey: "muteOtherAudioWhileDictating")
    }

    public var screenContextEnabled: Bool {
        Self.defaults.object(forKey: "screenContextEnabled") as? Bool ?? true
    }

    public func setScreenContextEnabled(_ enabled: Bool) {
        Self.set(enabled, forKey: "screenContextEnabled")
    }

    public var preferredInputDeviceUID: String? {
        Self.defaults.string(forKey: "preferredInputDeviceUID")
    }

    public func setPreferredInputDeviceUID(_ uid: String?) {
        Self.set(uid, forKey: "preferredInputDeviceUID")
    }

    /// The dictation key. `dictationTrigger` (JSON) wins; installs from before
    /// combos were allowed still carry the bare key under `hotkeyKey`.
    public var dictationTrigger: DictationTrigger {
        if let data = Self.defaults.data(forKey: "dictationTrigger"),
           let trigger = try? JSONDecoder().decode(DictationTrigger.self, from: data) {
            return trigger
        }
        if let key = Self.defaults.string(forKey: "hotkeyKey").flatMap(HotkeyKey.init(rawValue:)) {
            return .modifier(key)
        }
        return .default
    }

    // MARK: - Formatting policy

    /// How a dictation gets formatted. Two independent flags rather than a
    /// three-valued enum, because all four combinations are meaningful — in
    /// particular (nativeSmart: false, cleanupPass: true) is the exact pipeline
    /// VoiceiQ shipped before native smart existed, and that is the configuration you
    /// want reachable if smart mode ever regresses server-side.
    public struct FormattingPolicy: Equatable, Sendable {
        public var nativeSmart: Bool
        public var cleanupPass: Bool

        public init(nativeSmart: Bool, cleanupPass: Bool) {
            self.nativeSmart = nativeSmart
            self.cleanupPass = cleanupPass
        }

        public var mode: GeminiClient.TranscriptionMode { nativeSmart ? .smart : .verbatim }
        /// The gate only has a real reference to compare against when a second
        /// model actually rewrote the text.
        public var runsValidationGate: Bool { cleanupPass }
    }

    public var formattingPolicy: FormattingPolicy {
        FormattingPolicy(
            nativeSmart: Self.defaults.object(forKey: "smartTranscription") as? Bool ?? true,
            cleanupPass: Self.defaults.object(forKey: "smartCleanupPass") as? Bool ?? true
        )
    }

    /// Native `mode: "smart"` — the default transcription path.
    public var smartTranscriptionEnabled: Bool {
        Self.defaults.object(forKey: "smartTranscription") as? Bool ?? true
    }

    public func setSmartTranscription(_ enabled: Bool) {
        Self.set(enabled, forKey: "smartTranscription")
    }

    /// The second pass through the cleanup model — this is what applies the
    /// user's writing rules (`customInstructions`) and per-app tone. On by
    /// default: native smart transcription cannot apply a correction spoken
    /// several sentences after the thing it corrects, and cannot segment
    /// pause-free speech by grammar. It costs a round trip and sends the
    /// transcript text a second time.
    public var smartCleanupPassEnabled: Bool {
        Self.defaults.object(forKey: "smartCleanupPass") as? Bool ?? true
    }

    /// Free-form rules the cleanup pass follows. Empty or whitespace means
    /// "use `DictationRulesSeed.text`", so a user who clears the box gets the
    /// defaults rather than a rule-less pass.
    public var customInstructions: String {
        let stored = Self.defaults.string(forKey: "customInstructions") ?? ""
        return stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? DictationRulesSeed.text
            : stored
    }

    /// The raw stored value for the editor (nil until the user edits).
    public var customInstructionsOverride: String? {
        Self.defaults.string(forKey: "customInstructions")
    }

    public func setCustomInstructions(_ text: String?) {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        Self.set(trimmed.flatMap { $0.isEmpty ? nil : $0 }, forKey: "customInstructions")
    }

    /// Watch the field after insertion and add the user's word-level edits to
    /// the dictionary automatically.
    public var autoLearnEnabled: Bool {
        Self.defaults.object(forKey: "autoLearn") as? Bool ?? true
    }

    public func setAutoLearn(_ enabled: Bool) {
        Self.set(enabled, forKey: "autoLearn")
    }

    /// Detect calls (mic in use by a call app or a meeting tab) and record
    /// them for meeting notes.
    public var meetingDetectionEnabled: Bool {
        Self.defaults.object(forKey: "meetingDetection") as? Bool ?? true
    }

    public func setMeetingDetection(_ enabled: Bool) {
        Self.set(enabled, forKey: "meetingDetection")
    }

    /// Only the user changes this. Rejected rewrites never turn it off.
    public func setSmartCleanupPass(_ enabled: Bool) {
        Self.set(enabled, forKey: "smartCleanupPass")
    }

    /// Escape hatch back to the pre-native-smart transport.
    ///
    /// `/v1beta/interactions` is days old. For the cost of one settings row, a
    /// server-side regression in smart mode becomes something a user can switch
    /// off rather than something that needs a hotfix release. Smart formatting is
    /// unavailable on the legacy endpoint (`mode` returns an empty transcript
    /// there), so this necessarily means verbatim + the optional tone pass.
    /// Remove once native smart has a clean dogfood run.
    public var usesLegacyTranscribeEndpoint: Bool {
        Self.defaults.bool(forKey: "legacyTranscribeEndpoint")
    }

    public func setLegacyTranscribeEndpoint(_ enabled: Bool) {
        Self.set(enabled, forKey: "legacyTranscribeEndpoint")
    }

    public func setDictationTrigger(_ trigger: DictationTrigger) {
        Self.set(try? JSONEncoder().encode(trigger), forKey: "dictationTrigger")
    }

    /// Experimental: judge speech RELATIVE to the room instead of against fixed
    /// thresholds that assume a quiet one, and (once probed) let macOS suppress
    /// background voices. Off by default until dogfood data earns the flip.
    ///
    /// One key gates every behaviour in the noise work, so there is exactly one
    /// thing to turn on, one thing to turn off, and one thing to flip when the
    /// numbers are in. The measurements it would act on are recorded either way —
    /// `NoiseFloorEstimator` runs unconditionally.
    public var experimentalNoiseHandling: Bool {
        Self.defaults.bool(forKey: "experimentalNoiseHandling")
    }

    public func setExperimentalNoiseHandling(_ enabled: Bool) {
        Self.set(enabled, forKey: "experimentalNoiseHandling")
    }

    /// Stream audio to the Live API over a WebSocket and show words as they are
    /// spoken, instead of uploading the clip at key-up.
    ///
    /// Off by default: the live model draws on its own, small daily request
    /// quota, and a long dictation rotates through several sessions. When on,
    /// the CAF is still written to disk in parallel, and any live stream that
    /// fails falls back to the batch upload over that file.
    public var liveTranscription: Bool {
        Self.defaults.object(forKey: "liveTranscription") as? Bool ?? false
    }

    public func setLiveTranscription(_ enabled: Bool) {
        Self.set(enabled, forKey: "liveTranscription")
    }

    /// Live needs the interactions-era transport; the legacy escape hatch is a
    /// different endpoint entirely. Rather than let the two contradict each other
    /// silently, the hatch wins and live stands down.
    public var liveTranscriptionActive: Bool {
        liveTranscription && !usesLegacyTranscribeEndpoint && liveTranscriptionSupported
    }

    /// With ElevenLabs on any route; otherwise only over a provider's own API
    /// (see `ModelRoute.supportsLiveTranscription`).
    public var liveTranscriptionSupported: Bool {
        transcriptionSource == .elevenLabs || activeRoute.supportsLiveTranscription
    }

    // Raw override values for the Settings UI — panes must not duplicate the
    // defaults keys (a rename would silently desync display from effect).
    public var endpointOverride: String? { Self.defaults.string(forKey: "endpointOverride") }
    public var transcribeModelOverride: String? { Self.defaults.string(forKey: "transcribeModelOverride") }
    public var liveModelOverride: String? { Self.defaults.string(forKey: "liveModelOverride") }
    public var cleanupModelOverride: String? { Self.defaults.string(forKey: "cleanupModelOverride") }

    public func setEndpointOverride(_ raw: String?) {
        Self.set(raw, forKey: "endpointOverride")
    }

    public func setTranscribeModelOverride(_ raw: String?) {
        Self.set(raw, forKey: "transcribeModelOverride")
    }

    public func setLiveModelOverride(_ raw: String?) {
        Self.set(raw, forKey: "liveModelOverride")
    }

    public func setCleanupModelOverride(_ raw: String?) {
        Self.set(raw, forKey: "cleanupModelOverride")
    }

    /// Days to keep audio files (transcripts are kept until deleted). 0 = forever.
    public var audioRetentionDays: Int {
        Self.defaults.object(forKey: "audioRetentionDays") as? Int ?? 7
    }

    public func setAudioRetentionDays(_ days: Int) {
        Self.set(days, forKey: "audioRetentionDays")
    }
}
