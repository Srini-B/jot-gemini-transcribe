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
    /// next unrelated transition". (gateTrips bookkeeping is exempt: nothing
    /// renders it.)
    static let gtSettingDidChange = Notification.Name("io.blue.voiceiq.setting-changed")

    /// Posted when the gate auto-disables the opt-in tone pass (3 trips in 24h)
    /// so the app can tell the user instead of silently dropping it. Native smart
    /// transcription is unaffected — the user loses an extra, not their words.
    static let gtSmartFormattingAutoDegraded = Notification.Name("io.blue.voiceiq.auto-degraded")
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

    /// Double-tap the dictation key to lock hands-free. OFF by default: firm taps
    /// routinely exceed the hold threshold, misreading tap-tap as hold→finalize
    /// (dogfood). The timing-free gesture is Space-while-holding.
    public var doubleTapLockEnabled: Bool {
        Self.defaults.object(forKey: "doubleTapLock") as? Bool ?? false
    }

    public func setDoubleTapLock(_ enabled: Bool) {
        Self.set(enabled, forKey: "doubleTapLock")
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

    public var hotkeyKey: HotkeyKey {
        (Self.defaults.string(forKey: "hotkeyKey")).flatMap(HotkeyKey.init(rawValue:)) ?? .fn
    }

    // MARK: - Formatting policy

    /// How a dictation gets formatted. Two independent flags rather than a
    /// three-valued enum, because all four combinations are meaningful — in
    /// particular (nativeSmart: false, cleanupPass: true) is the exact pipeline
    /// Voice IQ shipped before native smart existed, and that is the configuration you
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

    public func setSmartCleanupPass(_ enabled: Bool) {
        if enabled {
            // A deliberate re-enable is a clean slate. This moved here with the
            // gate counter: auto-degrade now switches THIS flag off, so leaving
            // the clear on setSmartFormatting would resurrect the bug where one
            // stale trip inside the old 24h window instantly re-degrades.
            Self.defaults.removeObject(forKey: "gateTrips")
        }
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

    public func setHotkeyKey(_ key: HotkeyKey) {
        Self.set(key.rawValue, forKey: "hotkeyKey")
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
    /// On by default: the CAF is written to disk in parallel, and any live stream
    /// that fails, drops chunks, or misses byte reconciliation automatically falls
    /// back to the batch upload over that file.
    public var liveTranscription: Bool {
        Self.defaults.object(forKey: "liveTranscription") as? Bool ?? true
    }

    public func setLiveTranscription(_ enabled: Bool) {
        Self.set(enabled, forKey: "liveTranscription")
    }

    /// Live needs the interactions-era transport; the legacy escape hatch is a
    /// different endpoint entirely. Rather than let the two contradict each other
    /// silently, the hatch wins and live stands down.
    public var liveTranscriptionActive: Bool {
        liveTranscription && !usesLegacyTranscribeEndpoint
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

    /// Auto-degrade bookkeeping (F11): ≥3 gate trips in 24h ⇒ verbatim by default.
    public func recordGateTrip(now: Date = Date()) -> Int {
        var trips = (Self.defaults.array(forKey: "gateTrips") as? [Date]) ?? []
        trips = trips.filter { now.timeIntervalSince($0) < 86_400 }
        trips.append(now)
        Self.defaults.set(trips, forKey: "gateTrips")
        return trips.count
    }
}
