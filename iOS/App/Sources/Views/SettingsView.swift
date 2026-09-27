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
import VoiceIQBridge
import VoiceIQCore

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink { KeysView() } label: { Label("API Keys", systemImage: "key") }
                    NavigationLink { DictationSettingsView() } label: { Label("Dictation", systemImage: "waveform") }
                    NavigationLink { DictionaryView() } label: { Label("Dictionary", systemImage: "character.book.closed") }
                    NavigationLink { ReturnAppsView() } label: { Label("Return to Apps", systemImage: "arrow.uturn.backward.circle") }
                    NavigationLink { KeyboardSetupView() } label: { Label("Keyboard", systemImage: "keyboard") }
                }
                Section {
                    NavigationLink { PrivacyView() } label: { Label("Privacy", systemImage: "hand.raised") }
                    NavigationLink { UsageView() } label: { Label("Cost", systemImage: "chart.bar") }
                    NavigationLink { AdvancedView() } label: { Label("Advanced", systemImage: "slider.horizontal.3") }
                }
                Section {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                }
            }
            .navigationTitle("Settings")
        }
    }
}

struct DictationSettingsView: View {
    @EnvironmentObject private var session: VoiceSession
    private let settings = SettingsStore()
    @State private var translationTarget = SettingsStore().translationTargetLanguage
    @State private var smartTranscription = SettingsStore().smartTranscriptionEnabled
    @State private var cleanupPass = SettingsStore().smartCleanupPassEnabled
    @State private var instructions = SettingsStore().customInstructions
    @State private var liveTranscription = SettingsStore().liveTranscription
    @State private var noiseHandling = SettingsStore().experimentalNoiseHandling
    @State private var builtInMic = MobileSettings.preferBuiltInMic

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    LanguageList(selected: $translationTarget)
                } label: {
                    LabeledContent("Translate to", value: translationTarget)
                }
                .onChange(of: translationTarget) { _, value in settings.setTranslationTargetLanguage(value) }
                Toggle("Use iPhone microphone", isOn: $builtInMic)
                    .onChange(of: builtInMic) { _, value in
                        MobileSettings.preferBuiltInMic = value
                        session.setPreferBuiltInMic(value)
                    }
            }
            Section {
                Toggle("Smart transcription", isOn: $smartTranscription)
                    .onChange(of: smartTranscription) { _, value in settings.setSmartTranscription(value) }
                Toggle("Apply writing rules", isOn: $cleanupPass)
                    .onChange(of: cleanupPass) { _, value in settings.setSmartCleanupPass(value) }
                if cleanupPass {
                    NavigationLink("Writing rules") { WritingRulesView(text: $instructions) }
                }
            }
            Section("Experimental") {
                Toggle("Better hearing in loud rooms", isOn: $noiseHandling)
                    .onChange(of: noiseHandling) { _, value in settings.setExperimentalNoiseHandling(value) }
                Toggle("Live transcription", isOn: $liveTranscription)
                    .onChange(of: liveTranscription) { _, value in settings.setLiveTranscription(value) }
                    .disabled(settings.usesLegacyTranscribeEndpoint)
            }
        }
        .navigationTitle("Dictation")
    }
}

private struct WritingRulesView: View {
    @Binding var text: String

    var body: some View {
        Form {
            TextEditor(text: $text)
                .frame(minHeight: 320)
                .font(.callout)
            Button("Restore defaults") {
                SettingsStore().setCustomInstructions(nil)
                text = SettingsStore().customInstructions
            }
        }
        .navigationTitle("Writing Rules")
        .onDisappear { SettingsStore().setCustomInstructions(text) }
    }
}

private struct LanguageList: View {
    @Binding var selected: String
    @State private var search = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List(GeminiLanguages.supported.filter {
            search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)
        }) { language in
            Button {
                selected = language.name
                dismiss()
            } label: {
                HStack {
                    Text(language.name).foregroundStyle(.primary)
                    Spacer()
                    if language.name == selected { Image(systemName: "checkmark") }
                }
            }
        }
        .searchable(text: $search)
        .navigationTitle("Translate To")
    }
}

struct DictionaryView: View {
    @State private var entries = DictionaryStore().entries()
    @State private var newTerm = ""
    @State private var misspelling = ""

    var body: some View {
        Form {
            Section {
                TextField("Word or name", text: $newTerm)
                    .textInputAutocapitalization(.never)
                TextField("Often heard as (optional)", text: $misspelling)
                    .textInputAutocapitalization(.never)
                Button("Add") {
                    let term = newTerm.trimmingCharacters(in: .whitespacesAndNewlines)
                    let wrong = misspelling.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !term.isEmpty else { return }
                    _ = DictionaryStore().add(term: term, misspelling: wrong.isEmpty ? nil : wrong)
                    newTerm = ""
                    misspelling = ""
                    entries = DictionaryStore().entries()
                }
                .disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Section {
                ForEach(entries) { entry in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(entry.term)
                            if let wrong = entry.misspelling {
                                Text(wrong).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button {
                            DictionaryStore().toggleStar(id: entry.id)
                            entries = DictionaryStore().entries()
                        } label: {
                            Image(systemName: entry.starred ? "star.fill" : "star")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .onDelete { offsets in
                    for index in offsets { DictionaryStore().remove(id: entries[index].id) }
                    entries = DictionaryStore().entries()
                }
            }
        }
        .navigationTitle("Dictionary")
    }
}

/// Every app the keyboard was used in and whether VoiceiQ can send the user
/// back to it after the one-time bounce.
struct ReturnAppsView: View {
    @EnvironmentObject private var hostReturn: HostReturn

    var body: some View {
        List {
            if hostReturn.records.isEmpty {
                Text("Apps you dictate in appear here")
                    .foregroundStyle(.secondary)
            }
            ForEach(hostReturn.records) { record in
                NavigationLink {
                    ReturnAppDetail(record: record)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(AppNames.displayName(for: record.bundleID))
                        Text(statusText(record))
                            .font(.caption)
                            .foregroundStyle(record.lastReturn == .noScheme || record.lastReturn == .openFailed ? Brand.recording : .secondary)
                    }
                }
            }
        }
        .navigationTitle("Return to Apps")
    }

    private func statusText(_ record: HostReturn.Record) -> String {
        if hostReturn.returnURL(for: record.bundleID) != nil, record.lastReturn != .openFailed {
            return "Returns automatically"
        }
        return (record.lastReturn ?? .noScheme).label
    }
}

private struct ReturnAppDetail: View {
    @EnvironmentObject private var hostReturn: HostReturn
    let record: HostReturn.Record
    @State private var custom = ""

    var body: some View {
        Form {
            Section {
                LabeledContent("Bundle ID") {
                    Text(record.bundleID).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                }
                LabeledContent("Dictations", value: record.uses.formatted())
                if let url = KnownAppSchemes.returnURL(forHostId: record.bundleID) {
                    LabeledContent("Built-in link", value: url.absoluteString)
                }
            }
            Section("Custom return link") {
                TextField("app-scheme://", text: $custom)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { hostReturn.setOverride(custom, for: record.bundleID) }
                Button("Save") { hostReturn.setOverride(custom, for: record.bundleID) }
            }
            Section {
                Button("Forget", role: .destructive) { hostReturn.forget(record.bundleID) }
            }
        }
        .navigationTitle(AppNames.displayName(for: record.bundleID))
        .onAppear { custom = hostReturn.overrides[record.bundleID] ?? "" }
    }
}

struct PrivacyView: View {
    @State private var retentionDays = SettingsStore().audioRetentionDays

    var body: some View {
        Form {
            Section {
                Picker("Keep audio recordings", selection: $retentionDays) {
                    Text("Never").tag(-1)
                    Text("24 hours").tag(1)
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                    Text("Forever").tag(0)
                }
                .onChange(of: retentionDays) { _, days in
                    SettingsStore().setAudioRetentionDays(days)
                    Task.detached(priority: .utility) { RetentionPolicy().purgeExpiredAudio() }
                }
            }
            Section("What leaves your iPhone") {
                LabeledContent("Audio", value: "Your model provider")
                LabeledContent("Dictionary terms", value: "Your model provider")
                LabeledContent("Ask search queries", value: "TinyFish, if its key is saved")
                LabeledContent("What you type", value: "Never")
            }
        }
        .navigationTitle("Privacy")
    }
}

struct UsageView: View {
    @State private var total = UsageMeter.store?.total() ?? .zero
    @State private var byActivity = UsageMeter.store?.totalsByActivity() ?? []

    var body: some View {
        Form {
            Section {
                LabeledContent("Total", value: total.costUSD.formatted(.currency(code: "USD").precision(.fractionLength(2...4))))
                LabeledContent("Requests", value: total.calls.formatted())
            }
            Section("By activity") {
                ForEach(byActivity, id: \.key) { item in
                    LabeledContent(UsageActivity(rawValue: item.key)?.displayName ?? item.key,
                                   value: item.total.costUSD.formatted(.currency(code: "USD").precision(.fractionLength(2...4))))
                }
            }
            Section {
                Text(SettingsStore().activeProvider.pricingNote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Cost")
    }
}

struct AdvancedView: View {
    private let settings = SettingsStore()
    @State private var endpoint = SettingsStore().endpointOverride ?? ""
    @State private var transcribeModel = SettingsStore().transcribeModelOverride ?? ""
    @State private var liveModel = SettingsStore().liveModelOverride ?? ""
    @State private var cleanupModel = SettingsStore().cleanupModelOverride ?? ""
    @State private var legacyEndpoint = SettingsStore().usesLegacyTranscribeEndpoint
    private let defaults = GeminiConfig()

    var body: some View {
        Form {
            Section("Model overrides") {
                field("Endpoint", text: $endpoint, prompt: defaults.endpoint.absoluteString) { settings.setEndpointOverride($0) }
                field("Transcription", text: $transcribeModel, prompt: defaults.transcribeModel) { settings.setTranscribeModelOverride($0) }
                field("Live", text: $liveModel, prompt: defaults.liveModel) { settings.setLiveModelOverride($0) }
                field("Formatting", text: $cleanupModel, prompt: defaults.cleanupModel) { settings.setCleanupModelOverride($0) }
            }
            Section {
                Toggle("Use the previous transcription endpoint", isOn: $legacyEndpoint)
                    .onChange(of: legacyEndpoint) { _, value in settings.setLegacyTranscribeEndpoint(value) }
            }
        }
        .navigationTitle("Advanced")
    }

    private func field(_ label: String, text: Binding<String>, prompt: String, save: @escaping (String?) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField("", text: text, prompt: Text(prompt))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(.footnote, design: .monospaced))
                .onChange(of: text.wrappedValue) { _, value in
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    save(trimmed.isEmpty ? nil : trimmed)
                }
        }
    }
}
