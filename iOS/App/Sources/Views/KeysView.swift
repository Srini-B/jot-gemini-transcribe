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

import SwiftUI
import VoiceIQCore

/// Provider keys, stored in the Keychain and only sent to that provider.
struct KeysView: View {
    @State private var preferred = SettingsStore().preferredProvider
    @State private var available = KeychainStore.providersWithKeys

    var body: some View {
        Form {
            if available.count > 1 {
                Section {
                    Picker("Provider", selection: $preferred) {
                        ForEach(ModelProvider.allCases.filter(available.contains)) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .onChange(of: preferred) { _, value in SettingsStore().setPreferredProvider(value) }
                }
            }
            ForEach(ModelProvider.allCases) { provider in
                Section(provider.displayName) {
                    KeyForm(provider: provider) { available = KeychainStore.providersWithKeys }
                }
            }
            Section("TinyFish") {
                KeyForm(provider: nil) {}
            }
        }
        .navigationTitle("API Keys")
    }
}

/// One key field with validation. `provider == nil` is the TinyFish search key.
struct KeyForm: View {
    let provider: ModelProvider?
    let onChange: () -> Void

    @State private var text = ""
    @State private var stored = false
    @State private var checking = false
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SecureField(stored ? "Saved in Keychain" : "Paste your key", text: $text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
                if checking {
                    ProgressView()
                } else if stored && text.isEmpty {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
            }
            HStack {
                Button("Save") { Task { await save() } }
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || checking)
                if stored {
                    Button("Remove", role: .destructive) { remove() }
                }
                Spacer()
                Link("Get a key", destination: keyURL)
                    .font(.subheadline)
            }
            .buttonStyle(.borderless)
            if let message {
                Text(message).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .onAppear { stored = load() != nil }
    }

    private var keyURL: URL {
        switch provider {
        case .gemini: return URL(string: "https://aistudio.google.com/apikey")!
        case .openRouter: return URL(string: "https://openrouter.ai/settings/keys")!
        case .vercel: return URL(string: "https://vercel.com/ai-gateway")!
        case nil: return URL(string: "https://agent.tinyfish.ai/api-keys")!
        }
    }

    private func load() -> String? {
        switch provider {
        case .gemini: return KeychainStore.loadAPIKey()
        case .openRouter: return KeychainStore.loadOpenRouterKey()
        case .vercel: return KeychainStore.loadVercelKey()
        case nil: return KeychainStore.loadTinyFishKey()
        }
    }

    private func remove() {
        switch provider {
        case .gemini: KeychainStore.deleteAPIKey(notify: true)
        case .openRouter: KeychainStore.deleteOpenRouterKey(notify: true)
        case .vercel: KeychainStore.deleteVercelKey(notify: true)
        case nil: KeychainStore.deleteTinyFishKey(notify: true)
        }
        stored = false
        message = nil
        onChange()
    }

    private func save() async {
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines)
        checking = true
        defer { checking = false }
        let accepted: Bool
        let offline: Bool
        switch provider {
        case .some(let provider):
            let check: GeminiClient.KeyCheck
            switch provider {
            case .gemini:
                check = await GeminiClient(apiKey: { key }).validateKey(endpoint: SettingsStore().geminiConfig.endpoint)
            case .openRouter:
                check = await GeminiClient(apiKey: { nil }, openRouterKey: { key }).validateOpenRouterKey()
            case .vercel:
                check = await GeminiClient(apiKey: { nil }, vercelKey: { key }).validateVercelKey()
            }
            switch check {
            case .valid: accepted = true; offline = false
            case .unreachable: accepted = true; offline = true
            case .rejected(let detail):
                message = detail ?? "\(provider.displayName) rejected that key"
                return
            }
        case nil:
            switch await TinyFishClient(apiKey: { key }).validateKey() {
            case .valid: accepted = true; offline = false
            case .unreachable: accepted = true; offline = true
            case .rejected:
                message = "TinyFish rejected that key"
                return
            }
        }
        guard accepted else { return }
        let saved: Bool
        switch provider {
        case .gemini: saved = KeychainStore.saveAPIKey(key)
        case .openRouter: saved = KeychainStore.saveOpenRouterKey(key)
        case .vercel: saved = KeychainStore.saveVercelKey(key)
        case nil: saved = KeychainStore.saveTinyFishKey(key)
        }
        guard saved else {
            message = "Couldn't save to the Keychain"
            return
        }
        text = ""
        stored = true
        message = offline ? "Saved. It will be checked on your first dictation." : nil
        onChange()
    }
}
