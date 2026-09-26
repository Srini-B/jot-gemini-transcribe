// Copyright 2026 Google LLC
// Licensed under the Apache License, Version 2.0.

import VoiceIQCore
import SwiftUI

/// Settings → Advanced: the TinyFish key that lets Ask Anything search the
/// web. Same save-and-validate flow as the Gemini key.
struct TinyFishKeySection: View {
    @State private var apiKey = ""
    @State private var keyStatus: AdvancedPane.KeyStatus = KeychainStore.loadTinyFishKey() == nil ? .missing : .stored

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
            if keyStatus == .invalid, KeychainStore.loadTinyFishKey() != nil {
                Text("That key didn't work — your saved key is unchanged.")
                    .font(VoiceIQUI.TypeScale.labelSmall())
                    .foregroundStyle(VoiceIQUI.Colors.error)
            }
            if keyStatus == .invalid, KeychainStore.loadTinyFishKey() == nil {
                Text("TinyFish rejected that key, or the account has no Search access.")
                    .font(VoiceIQUI.TypeScale.labelSmall())
                    .foregroundStyle(VoiceIQUI.Colors.error)
            }
            if keyStatus == .saveFailed {
                Text("The key validated but couldn't be saved to your Keychain — try again.")
                    .font(VoiceIQUI.TypeScale.labelSmall())
                    .foregroundStyle(VoiceIQUI.Colors.error)
            }
            if keyStatus == .savedOffline {
                Text("You look offline — key saved; it'll be checked on your first Ask Anything.")
                    .font(VoiceIQUI.TypeScale.labelSmall())
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("Save & Validate") { saveAndValidate() }
                    .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
                if hasStoredKey {
                    Button("Remove Key…", role: .destructive) { removeKey() }
                }
                Spacer()
                Link("Get a key at TinyFish", destination: URL(string: "https://agent.tinyfish.ai/api-keys")!)
                    .font(VoiceIQUI.TypeScale.labelSmall())
            }
        } header: {
            Text("TinyFish API key")
        } footer: {
            Text("Optional. Lets Ask Anything look up current information on the web. Stored in your Mac's Keychain and only ever sent to TinyFish.")
        }
        .onReceive(NotificationCenter.default.publisher(for: .gtSettingDidChange).receive(on: RunLoop.main)) { note in
            if note.object as? String == KeychainStore.Secret.tinyFish.settingKey, keyStatus == .missing || keyStatus == .stored {
                keyStatus = KeychainStore.loadTinyFishKey() == nil ? .missing : .stored
            }
        }
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
            let check = await TinyFishClient(apiKey: { key }).validateKey()
            switch check {
            case .valid, .unreachable:
                if KeychainStore.saveTinyFishKey(key) {
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

    private func removeKey() {
        KeychainStore.deleteTinyFishKey(notify: true)
        apiKey = ""
        keyStatus = .missing
    }
}
