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

/// Settings › API Keys.
struct KeysView: View {
    var body: some View {
        ScrollView {
            ModelKeysForm()
                .padding(.horizontal, Theme.Spacing.page)
                .padding(.vertical, Theme.Spacing.l)
        }
        .keyboardDismissable()
        .themedBackground()
        .navigationTitle("API Keys")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Every key on one page: the three model providers (one is enough) and the
/// optional TinyFish key, with the provider picker once two or more are saved.
struct ModelKeysForm: View {
    @State private var saved = KeySlot.savedSlots()
    @State private var preferred = SettingsStore().activeRoute.gateway

    private var savedGateways: [ModelGateway] {
        ModelGateway.allCases.filter { saved.contains(KeySlot(gateway: $0)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            HStack(alignment: .top, spacing: Theme.Spacing.m) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(Theme.Colors.accent)
                    .font(.system(size: 17))
                Text("Add a key for **one** provider: Gemini or OpenRouter or Vercel AI Gateway. You don't need all three. The TinyFish key is optional.")
                    .font(Theme.Fonts.subheadline())
                    .foregroundStyle(Theme.Colors.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Theme.Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.Colors.accent.opacity(0.08)))

            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                GroupLabel(text: "Model provider · one is enough")
                if savedGateways.count > 1 {
                    Card {
                        Text("Gateway").font(Theme.Fonts.headline()).foregroundStyle(Theme.Colors.ink)
                        Picker("Gateway", selection: $preferred) {
                            ForEach(savedGateways) { gateway in
                                Text(gateway.shortName).tag(gateway)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: preferred) { _, value in SettingsStore().setPreferredGateway(value) }
                    }
                }
                ForEach([KeySlot.gemini, .openRouter, .vercel], id: \.self) { slot in
                    KeyCard(slot: slot, onChange: reload)
                }
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                GroupLabel(text: "Optional")
                KeyCard(slot: .tinyFish, onChange: reload)
            }
        }
    }

    private func reload() {
        saved = KeySlot.savedSlots()
        preferred = SettingsStore().activeRoute.gateway
    }
}

private extension ModelGateway {
    /// The iPhone app runs Gemini only, so the direct route is Gemini's key.
    var shortName: String {
        switch self {
        case .direct: return "Gemini"
        case .openRouter: return "OpenRouter"
        case .vercel: return "Vercel"
        }
    }
}

/// One saved-or-not key, with its purpose, a field and its actions.
private struct KeyCard: View {
    let slot: KeySlot
    let onChange: () -> Void

    @State private var text = ""
    @State private var stored = false
    @State private var replacing = false
    @State private var checking = false
    @State private var message: String?
    @FocusState private var focused: Bool

    var body: some View {
        Card {
            HStack(spacing: Theme.Spacing.m) {
                IconTile(systemImage: slot.symbol, size: 32)
                Text(slot.title).font(Theme.Fonts.headline()).foregroundStyle(Theme.Colors.ink)
                Spacer(minLength: 0)
                if stored {
                    StatusChip(text: "Saved", tone: .done)
                } else {
                    Link(destination: slot.keyURL) {
                        Label("Get a key", systemImage: "arrow.up.right")
                            .labelStyle(TrailingIconLabelStyle())
                            .font(Theme.Fonts.label())
                            .foregroundStyle(Theme.Colors.accent)
                    }
                }
            }
            Text(slot.purpose)
                .font(Theme.Fonts.footnote())
                .foregroundStyle(Theme.Colors.muted)
                .fixedSize(horizontal: false, vertical: true)

            if stored && !replacing {
                HStack(spacing: Theme.Spacing.s) {
                    Text("••••••••••••")
                        .font(Theme.Fonts.code)
                        .foregroundStyle(Theme.Colors.muted)
                    Spacer(minLength: 0)
                    Button("Replace") { replacing = true; focused = true }.buttonStyle(.compactSecondary)
                    Button("Remove", action: remove).buttonStyle(.compactDestructive)
                }
                .padding(.leading, Theme.Spacing.m)
                .padding(.trailing, 6)
                .frame(minHeight: 48)
                .background(fieldBackground)
            } else {
                HStack(spacing: Theme.Spacing.s) {
                    SecureField("", text: $text, prompt: Text("Paste key").font(Theme.Fonts.callout()))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(Theme.Fonts.code)
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit { Task { await save() } }
                    if checking {
                        ProgressView().padding(.horizontal, Theme.Spacing.m)
                    } else {
                        Button("Save") { Task { await save() } }
                            .buttonStyle(.compactPrimary)
                            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(.leading, Theme.Spacing.m)
                .padding(.trailing, 6)
                .frame(minHeight: 48)
                .background(fieldBackground)
            }

            if let message {
                Text(message)
                    .font(Theme.Fonts.footnote())
                    .foregroundStyle(message.hasPrefix("Saved") ? Theme.Colors.muted : Theme.Colors.recording)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { stored = slot.load() != nil }
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.field, style: .continuous)
            .fill(Theme.Colors.surfaceNested)
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.field, style: .continuous)
                .strokeBorder(focused ? Theme.Colors.accent : Theme.Colors.hairline, lineWidth: focused ? 1.5 : 0.5))
    }

    private func remove() {
        slot.delete()
        stored = false
        replacing = false
        message = nil
        onChange()
    }

    private func save() async {
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !checking else { return }
        checking = true
        defer { checking = false }
        switch await slot.validate(key) {
        case .rejected(let detail):
            message = detail
            return
        case .accepted(let offline):
            guard slot.save(key) else {
                message = "Couldn't save to the Keychain. Try again."
                return
            }
            text = ""
            stored = true
            replacing = false
            focused = false
            message = offline ? "Saved. It will be checked on your first dictation." : nil
            onChange()
        }
    }
}

private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.title
            configuration.icon.imageScale(.small)
        }
    }
}

/// A place a key can be stored, with what it is for.
enum KeySlot: Hashable, CaseIterable {
    // `openAI` is not offered on iOS yet; the macOS app ships it first.
    case gemini, openRouter, vercel, openAI, tinyFish

    init(gateway: ModelGateway) {
        switch gateway {
        case .direct: self = .gemini
        case .openRouter: self = .openRouter
        case .vercel: self = .vercel
        }
    }

    static func savedSlots() -> Set<KeySlot> {
        Set(allCases.filter { $0.load() != nil })
    }

    var title: String {
        switch self {
        case .gemini: return "Gemini"
        case .openRouter: return "OpenRouter"
        case .vercel: return "Vercel AI Gateway"
        case .openAI: return "OpenAI"
        case .tinyFish: return "TinyFish"
        }
    }

    var symbol: String {
        switch self {
        case .gemini: return "sparkles"
        case .openRouter: return "arrow.triangle.branch"
        case .vercel: return "triangle.fill"
        case .openAI: return "circle.hexagongrid"
        case .tinyFish: return "globe"
        }
    }

    var purpose: String {
        switch self {
        case .gemini:
            return "Google's Gemini API, with a free tier. Stored in your iPhone's Keychain and only ever sent to Google."
        case .openRouter:
            return "Runs the same Gemini models through OpenRouter, which has no per-minute tier limits. Stored in your iPhone's Keychain and only ever sent to OpenRouter."
        case .vercel:
            return "Runs the same Gemini models through Vercel AI Gateway, billed per call. Stored in your iPhone's Keychain and only ever sent to Vercel."
        case .openAI:
            return "Uses OpenAI's own models instead of Gemini. Stored in your iPhone's Keychain and only ever sent to OpenAI."
        case .tinyFish:
            return "Lets Ask Anything look up current information on the web. Stored in your iPhone's Keychain and only ever sent to TinyFish."
        }
    }

    var keyURL: URL {
        switch self {
        case .gemini: return URL(string: "https://aistudio.google.com/apikey")!
        case .openRouter: return URL(string: "https://openrouter.ai/settings/keys")!
        case .vercel: return URL(string: "https://vercel.com/ai-gateway")!
        case .openAI: return URL(string: "https://platform.openai.com/api-keys")!
        case .tinyFish: return URL(string: "https://agent.tinyfish.ai/api-keys")!
        }
    }

    func load() -> String? {
        switch self {
        case .gemini: return KeychainStore.loadAPIKey()
        case .openRouter: return KeychainStore.loadOpenRouterKey()
        case .vercel: return KeychainStore.loadVercelKey()
        case .openAI: return KeychainStore.loadOpenAIKey()
        case .tinyFish: return KeychainStore.loadTinyFishKey()
        }
    }

    func save(_ key: String) -> Bool {
        switch self {
        case .gemini: return KeychainStore.saveAPIKey(key)
        case .openRouter: return KeychainStore.saveOpenRouterKey(key)
        case .vercel: return KeychainStore.saveVercelKey(key)
        case .openAI: return KeychainStore.saveOpenAIKey(key)
        case .tinyFish: return KeychainStore.saveTinyFishKey(key)
        }
    }

    func delete() {
        switch self {
        case .gemini: _ = KeychainStore.deleteAPIKey(notify: true)
        case .openRouter: _ = KeychainStore.deleteOpenRouterKey(notify: true)
        case .vercel: _ = KeychainStore.deleteVercelKey(notify: true)
        case .openAI: _ = KeychainStore.deleteOpenAIKey(notify: true)
        case .tinyFish: _ = KeychainStore.deleteTinyFishKey(notify: true)
        }
    }

    enum Validation { case accepted(offline: Bool), rejected(String) }

    func validate(_ key: String) async -> Validation {
        let check: GeminiClient.KeyCheck
        switch self {
        case .gemini:
            check = await GeminiClient(apiKey: { key }).validateKey(endpoint: SettingsStore().geminiConfig.endpoint)
        case .openRouter:
            check = await GeminiClient(apiKey: { nil }, openRouterKey: { key }).validateOpenRouterKey()
        case .vercel:
            check = await GeminiClient(apiKey: { nil }, vercelKey: { key }).validateVercelKey()
        case .openAI:
            check = await GeminiClient(apiKey: { nil }, openAIKey: { key }).validateOpenAIKey()
        case .tinyFish:
            switch await TinyFishClient(apiKey: { key }).validateKey() {
            case .valid: return .accepted(offline: false)
            case .unreachable: return .accepted(offline: true)
            case .rejected: return .rejected("TinyFish rejected that key, or the account has no Search access.")
            }
        }
        switch check {
        case .valid: return .accepted(offline: false)
        case .unreachable: return .accepted(offline: true)
        case .rejected(let detail): return .rejected(detail ?? "\(title) rejected that key.")
        }
    }
}
