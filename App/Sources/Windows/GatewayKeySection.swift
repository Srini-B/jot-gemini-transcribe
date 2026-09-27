// Copyright 2026 Google LLC
// Licensed under the Apache License, Version 2.0.

import VoiceIQCore
import SwiftUI

/// Settings → Advanced: a gateway key (OpenRouter or Vercel AI Gateway) with
/// the same save-and-validate flow as the Gemini key.
struct GatewayKeySection: View {
    struct Gateway {
        let provider: ModelProvider
        let load: () -> String?
        let save: (String) -> Bool
        let delete: () -> Void
        let validate: (GeminiClient) async -> GeminiClient.KeyCheck
        let client: (String) -> GeminiClient
        let keyURL: URL
        let footer: String

        static let openRouter = Gateway(
            provider: .openRouter,
            load: KeychainStore.loadOpenRouterKey,
            save: KeychainStore.saveOpenRouterKey,
            delete: { KeychainStore.deleteOpenRouterKey(notify: true) },
            validate: { await $0.validateOpenRouterKey() },
            client: { key in GeminiClient(apiKey: { nil }, openRouterKey: { key }) },
            keyURL: URL(string: "https://openrouter.ai/settings/keys")!,
            footer: "Optional. Runs the same Gemini models through OpenRouter, which has no per-minute tier limits. Stored in your Mac's Keychain and only ever sent to OpenRouter."
        )

        static let vercel = Gateway(
            provider: .vercel,
            load: KeychainStore.loadVercelKey,
            save: KeychainStore.saveVercelKey,
            delete: { KeychainStore.deleteVercelKey(notify: true) },
            validate: { await $0.validateVercelKey() },
            client: { key in GeminiClient(apiKey: { nil }, vercelKey: { key }) },
            keyURL: URL(string: "https://vercel.com/ai-gateway")!,
            footer: "Optional. Runs the same Gemini models through Vercel AI Gateway, billed per call. Stored in your Mac's Keychain and only ever sent to Vercel."
        )
    }

    let gateway: Gateway
    @State private var apiKey = ""
    @State private var keyStatus: AdvancedPane.KeyStatus

    init(_ gateway: Gateway) {
        self.gateway = gateway
        _keyStatus = State(initialValue: gateway.load() == nil ? .missing : .stored)
    }

    private var hasStoredKey: Bool { keyStatus == .stored || keyStatus == .valid || keyStatus == .savedOffline }

    var body: some View {
        Section {
            HStack {
                LabeledContent("API key") {
                    SecureField("", text: $apiKey, prompt: Text(hasStoredKey ? "••••••••  (stored in Keychain)" : "Paste your key"))
                        .labelsHidden()
                        .font(VoiceIQUI.TypeScale.code)
                        .multilineTextAlignment(.trailing)
                }
                keyStatusBadge
            }
            if keyStatus == .invalid {
                Text(gateway.load() != nil
                     ? "That key didn't work — your saved key is unchanged."
                     : "\(gateway.provider.displayName) rejected that key.")
                    .font(VoiceIQUI.TypeScale.labelSmall())
                    .foregroundStyle(VoiceIQUI.Colors.error)
            }
            if keyStatus == .saveFailed {
                Text("The key validated but couldn't be saved to your Keychain — try again.")
                    .font(VoiceIQUI.TypeScale.labelSmall())
                    .foregroundStyle(VoiceIQUI.Colors.error)
            }
            if keyStatus == .savedOffline {
                Text("You look offline — key saved; it'll be checked on your first dictation.")
                    .font(VoiceIQUI.TypeScale.labelSmall())
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("Save & Validate") { saveAndValidate() }
                    .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
                if hasStoredKey {
                    Button("Remove Key…", role: .destructive) { gateway.delete(); apiKey = ""; keyStatus = .missing }
                }
                Spacer()
                Link("Get a key at \(gateway.provider.displayName)", destination: gateway.keyURL)
                    .font(VoiceIQUI.TypeScale.labelSmall())
            }
        } header: {
            Text("\(gateway.provider.displayName) API key")
        } footer: {
            Text(footer)
        }
        .onReceive(NotificationCenter.default.publisher(for: .gtSettingDidChange).receive(on: RunLoop.main)) { note in
            guard let key = note.object as? String else { return }
            if key == secret.settingKey, keyStatus == .missing || keyStatus == .stored {
                keyStatus = gateway.load() == nil ? .missing : .stored
            }
        }
    }

    private var secret: KeychainStore.Secret {
        gateway.provider == .vercel ? .vercel : .openRouter
    }

    private var footer: String {
        guard hasStoredKey else { return gateway.footer }
        return gateway.footer + " Live transcription is unavailable while \(gateway.provider.displayName) is the active provider."
    }

    @ViewBuilder
    private var keyStatusBadge: some View {
        switch keyStatus {
        case .missing:
            Image(systemName: "key.slash").foregroundStyle(.secondary)
        case .stored, .savedOffline:
            Image(systemName: "checkmark.circle").foregroundStyle(.secondary)
        case .validating:
            ProgressView().controlSize(.small)
        case .valid:
            Image(systemName: "checkmark.circle").foregroundStyle(VoiceIQUI.Colors.success)
        case .invalid, .saveFailed:
            Image(systemName: "xmark.circle.fill").foregroundStyle(VoiceIQUI.Colors.error)
        }
    }

    private func saveAndValidate() {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        keyStatus = .validating
        Task {
            let check = await gateway.validate(gateway.client(key))
            switch check {
            case .valid, .unreachable:
                if gateway.save(key) {
                    apiKey = ""
                    keyStatus = check == .valid ? .valid : .savedOffline
                } else {
                    keyStatus = .saveFailed
                }
            case .rejected:
                keyStatus = .invalid
            }
        }
    }
}

/// Settings → Advanced: which provider serves the calls. Only providers with a
/// stored key are offered; with one key there is nothing to choose, so the
/// section stays out of the way.
struct ProviderSection: View {
    private let settings = SettingsStore()
    @State private var preferred = SettingsStore().preferredProvider
    @State private var available = KeychainStore.providersWithKeys

    var body: some View {
        if available.count > 1 {
            Section {
                Picker("Provider", selection: $preferred) {
                    ForEach(ModelProvider.allCases.filter(available.contains)) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .onChange(of: preferred) { _, value in settings.setPreferredProvider(value) }
            } header: {
                Text("Provider")
            }
            .onReceive(NotificationCenter.default.publisher(for: .gtSettingDidChange).receive(on: RunLoop.main)) { _ in
                available = KeychainStore.providersWithKeys
                preferred = settings.activeProvider
            }
        }
    }
}
