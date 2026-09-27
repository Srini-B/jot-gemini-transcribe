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

extension LiveTranscriber {
    /// Builds a live session, or nil — which is the normal answer, since live is
    /// experimental and off by default.
    ///
    /// Kept out of the coordinator, which should know about neither the Keychain
    /// nor the Dictionary. Shared by the macOS and iOS apps.
    @MainActor
    public static func makeFromSettings() -> LiveTranscribing? {
        let settings = SettingsStore()
        guard settings.liveTranscriptionActive else { return nil }
        // A live path that is reliably broken is worse than one that is off: every
        // attempt costs a handshake and then the full upload anyway, so the user
        // pays latency on every dictation for a feature that never delivers. Stop
        // trying after a run of failures; a single success clears the streak, so a
        // bad hotel wifi heals itself without anyone touching a setting.
        let stats = LiveStats()
        if stats.shouldStopTrying {
            Log.transcription.info(
                "live disabled for now after \(stats.consecutiveFailures) consecutive failures — uploading instead"
            )
            return nil
        }
        // Live is a Gemini WebSocket; the gateways have no equivalent, so the
        // upload path carries the whole dictation on those providers.
        guard settings.activeProvider == .gemini,
              let key = KeychainStore.loadAPIKey(), !key.isEmpty else { return nil }
        let dictionary = DictionaryStore()
        let liveModel = settings.geminiConfig.liveModel
        let session = LiveTranscriptionSession(
            transport: WebSocketTransport(apiKey: { key }),
            setup: LiveSetup(
                model: liveModel,
                smart: settings.smartTranscriptionEnabled,
                // The same terms the batch path biases with, so switching modes
                // does not quietly change how someone's name gets spelled.
                customVocabulary: dictionary.vocabulary()
            )
        )
        return LiveTranscriber(
            session: session,
            modelID: liveModel,
            replacementRules: { DictionaryStore().replacementRules() }
        )
    }
}
