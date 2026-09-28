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
    @EnvironmentObject private var setup: SetupMonitor

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: Theme.Spacing.s) {
                        Wordmark(height: 36)
                        Text(versionText)
                            .font(Theme.Fonts.caption())
                            .foregroundStyle(Theme.Colors.muted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.m)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                Section {
                    settingsLink("API Keys", icon: "key.fill", destination: KeysView()) {
                        if !KeychainStore.hasModelKey { StatusChip(text: "Missing", tone: .pending) }
                    }
                    settingsLink("Keyboard & Permissions", icon: "keyboard.fill", destination: KeyboardSetupView()) {
                        if !setup.status.keyboardReady || !setup.status.micGranted {
                            StatusChip(text: "Set up", tone: .pending)
                        }
                    }
                    settingsLink("Dictation", icon: "waveform", destination: DictationSettingsView())
                    settingsLink("Dictionary", icon: "character.book.closed.fill", destination: DictionaryView())
                    settingsLink("Return to Apps", icon: "arrow.uturn.backward", destination: ReturnAppsView())
                }
                .listRowBackground(Theme.Colors.surface)

                Section {
                    settingsLink("Privacy", icon: "hand.raised.fill", destination: PrivacyView())
                    settingsLink("Cost", icon: "chart.bar.fill", destination: UsageView())
                    settingsLink("Advanced", icon: "slider.horizontal.3", destination: AdvancedView())
                }
                .listRowBackground(Theme.Colors.surface)
            }
            .listStyle(.insetGrouped)
            .themedBackground()
            .navigationTitle("Settings")
            .onAppear { setup.refresh() }
        }
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return "Version \(version) (\(build))"
    }

    private func settingsLink<Destination: View, Trailing: View>(
        _ title: String,
        icon: String,
        destination: Destination,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        NavigationLink { destination } label: {
            HStack(spacing: Theme.Spacing.m) {
                IconTile(systemImage: icon)
                Text(title).font(Theme.Fonts.body()).foregroundStyle(Theme.Colors.ink)
                Spacer(minLength: Theme.Spacing.s)
                trailing()
            }
        }
    }

    private func settingsLink<Destination: View>(_ title: String, icon: String, destination: Destination) -> some View {
        settingsLink(title, icon: icon, destination: destination) { EmptyView() }
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
    @State private var warmWindow = MobileSettings.warmWindow

    var body: some View {
        Form {
            Section {
                Picker("Keep mic on after dictating", selection: $warmWindow) {
                    ForEach(MobileSettings.WarmWindow.allCases) { Text($0.label).tag($0) }
                }
                .onChange(of: warmWindow) { _, value in MobileSettings.warmWindow = value }
            } footer: {
                Text("While the mic is on, the next keyboard tap starts right away. After that, the tap opens VoiceiQ for a moment.")
            }
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
                if cleanupPass { NavigationLink("Writing rules") { WritingRulesView(text: $instructions) } }
            }
            Section {
                Toggle("Better hearing in loud rooms", isOn: $noiseHandling)
                    .onChange(of: noiseHandling) { _, value in settings.setExperimentalNoiseHandling(value) }
                Toggle("Live transcription", isOn: $liveTranscription)
                    .onChange(of: liveTranscription) { _, value in settings.setLiveTranscription(value) }
                    .disabled(settings.usesLegacyTranscribeEndpoint || !settings.liveTranscriptionSupported)
            } header: {
                SettingsSectionHeader("Experimental")
            } footer: {
                if !settings.liveTranscriptionSupported {
                    Text("Live transcription runs only with Google AI Studio as the provider.")
                }
            }
            Section {
                Text("Settings › Action Button › Controls › VoiceiQ Dictate. Press it to start dictating in any app and again to stop. It also works from Control Center.")
                    .font(Theme.Fonts.callout())
                    .foregroundStyle(Theme.Colors.ink)
                Button("Open Action Button settings", action: openActionButtonSettings)
                    .buttonStyle(.compactPrimary)
            } header: { SettingsSectionHeader("Action button") }
        }
        .settingsPage(title: "Dictation")
    }
}

/// Settings › Action Button. There is no public URL for it; `App-prefs:` is
/// the Settings app's own scheme. When iOS refuses it, VoiceiQ's page in
/// Settings opens instead.
private func openActionButtonSettings() {
    guard let url = URL(string: "App-prefs:ACTION_BUTTON") else { return }
    UIApplication.shared.open(url) { opened in
        if !opened, let fallback = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(fallback)
        }
    }
}

private struct WritingRulesView: View {
    @Binding var text: String

    var body: some View {
        Form {
            Section {
                TextEditor(text: $text)
                    .frame(minHeight: 320)
                    .font(Theme.Fonts.callout())
                    .scrollContentBackground(.hidden)
                    .padding(Theme.Spacing.s)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.field).fill(Theme.Colors.surfaceNested))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.field).strokeBorder(Theme.Colors.hairline, lineWidth: 0.5))
                HStack {
                    Spacer()
                    Button("Restore defaults") {
                        SettingsStore().setCustomInstructions(nil)
                        text = SettingsStore().customInstructions
                    }
                    .buttonStyle(.compactSecondary)
                }
            }
        }
        .settingsPage(title: "Writing Rules", keyboard: true)
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
                    Text(language.name).font(Theme.Fonts.body()).foregroundStyle(Theme.Colors.ink)
                    Spacer()
                    if language.name == selected {
                        Image(systemName: "checkmark").foregroundStyle(Theme.Colors.accent)
                    }
                }
            }
            .listRowBackground(Theme.Colors.surface)
        }
        .searchable(text: $search)
        .settingsPage(title: "Translate To", keyboard: true)
    }
}

struct DictionaryView: View {
    @State private var entries = DictionaryStore().entries()
    @State private var newTerm = ""
    @State private var misspelling = ""

    var body: some View {
        Form {
            Section {
                TextField("Word or name", text: $newTerm).textInputAutocapitalization(.never)
                TextField("Often heard as (optional)", text: $misspelling).textInputAutocapitalization(.never)
                HStack {
                    Spacer()
                    Button("Add", action: addEntry)
                        .buttonStyle(.compactPrimary)
                        .disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            Section {
                ForEach(entries) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Text(entry.term).font(Theme.Fonts.body()).foregroundStyle(Theme.Colors.ink)
                            if let wrong = entry.misspelling {
                                Text(wrong).font(Theme.Fonts.caption()).foregroundStyle(Theme.Colors.muted)
                            }
                        }
                        Spacer()
                        Button {
                            DictionaryStore().toggleStar(id: entry.id)
                            entries = DictionaryStore().entries()
                        } label: {
                            Image(systemName: entry.starred ? "star.fill" : "star")
                                .foregroundStyle(Theme.Colors.accent)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(entry.starred ? "Remove favorite" : "Add favorite")
                    }
                }
                .onDelete { offsets in
                    for index in offsets { DictionaryStore().remove(id: entries[index].id) }
                    entries = DictionaryStore().entries()
                }
            }
        }
        .settingsPage(title: "Dictionary", keyboard: true)
    }

    private func addEntry() {
        let term = newTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        let wrong = misspelling.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }
        _ = DictionaryStore().add(term: term, misspelling: wrong.isEmpty ? nil : wrong)
        newTerm = ""
        misspelling = ""
        entries = DictionaryStore().entries()
    }
}

struct ReturnAppsView: View {
    @EnvironmentObject private var hostReturn: HostReturn

    var body: some View {
        List {
            if hostReturn.records.isEmpty {
                Text("Apps you dictate in appear here")
                    .font(Theme.Fonts.body()).foregroundStyle(Theme.Colors.muted)
                    .listRowBackground(Theme.Colors.surface)
            }
            ForEach(hostReturn.records) { record in
                NavigationLink { ReturnAppDetail(record: record) } label: {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(AppNames.displayName(for: record.bundleID)).font(Theme.Fonts.body()).foregroundStyle(Theme.Colors.ink)
                        Text(statusText(record)).font(Theme.Fonts.caption())
                            .foregroundStyle(record.lastReturn == .noScheme || record.lastReturn == .openFailed ? Theme.Colors.recording : Theme.Colors.muted)
                    }
                }
                .listRowBackground(Theme.Colors.surface)
            }
        }
        .settingsPage(title: "Return to Apps")
    }

    private func statusText(_ record: HostReturn.Record) -> String {
        if hostReturn.returnURL(for: record.bundleID) != nil, record.lastReturn != .openFailed { return "Returns automatically" }
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
                    Text(record.bundleID).font(Theme.Fonts.code).textSelection(.enabled)
                }
                LabeledContent("Dictations", value: record.uses.formatted())
                if let url = KnownAppSchemes.returnURL(forHostId: record.bundleID) {
                    LabeledContent("Built-in link", value: url.absoluteString)
                }
            }
            Section {
                TextField("app-scheme://", text: $custom)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .onSubmit(saveOverride)
                HStack { Spacer(); Button("Save", action: saveOverride).buttonStyle(.compactPrimary) }
            } header: { SettingsSectionHeader("Custom return link") }
            Section {
                HStack {
                    Spacer()
                    Button("Forget") {
                        hostReturn.forget(record.bundleID)
                    }
                    .buttonStyle(.compactDestructive)
                    Spacer()
                }
            }
        }
        .settingsPage(title: AppNames.displayName(for: record.bundleID), keyboard: true)
        .onAppear { custom = hostReturn.overrides[record.bundleID] ?? "" }
    }

    private func saveOverride() { hostReturn.setOverride(custom, for: record.bundleID) }
}

struct PrivacyView: View {
    @State private var retentionDays = SettingsStore().audioRetentionDays

    var body: some View {
        Form {
            Section {
                Picker("Keep audio recordings", selection: $retentionDays) {
                    Text("Never").tag(-1); Text("24 hours").tag(1); Text("7 days").tag(7)
                    Text("30 days").tag(30); Text("Forever").tag(0)
                }
                .onChange(of: retentionDays) { _, days in
                    SettingsStore().setAudioRetentionDays(days)
                    Task.detached(priority: .utility) { RetentionPolicy().purgeExpiredAudio() }
                }
            }
            Section {
                LabeledContent("Audio", value: "Your model provider")
                LabeledContent("Dictionary terms", value: "Your model provider")
                LabeledContent("Ask search queries", value: "TinyFish, if its key is saved")
                LabeledContent("What you type", value: "Never")
            } header: { SettingsSectionHeader("What leaves your iPhone") }
        }
        .settingsPage(title: "Privacy")
    }
}

struct UsageView: View {
    @State private var total = UsageMeter.store?.total() ?? .zero
    @State private var byActivity = UsageMeter.store?.totalsByActivity() ?? []

    var body: some View {
        List {
            Section {
                Card {
                    Text(total.costUSD.formatted(.currency(code: "USD").precision(.fractionLength(2...4))))
                        .font(Theme.Fonts.numeric(40, weight: 250)).foregroundStyle(Theme.Colors.ink)
                    Text("\(total.calls.formatted()) requests")
                        .font(Theme.Fonts.caption()).foregroundStyle(Theme.Colors.muted)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            Section {
                ForEach(byActivity, id: \.key) { item in
                    LabeledContent(UsageActivity(rawValue: item.key)?.displayName ?? item.key,
                                   value: item.total.costUSD.formatted(.currency(code: "USD").precision(.fractionLength(2...4))))
                }
            } header: { SettingsSectionHeader("By activity") }
            Section {
                Text(SettingsStore().activeProvider.pricingNote)
                    .font(Theme.Fonts.footnote()).foregroundStyle(Theme.Colors.muted)
            }
        }
        .settingsPage(title: "Cost")
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
            Section {
                NavigationLink("Session log") { SessionLogView() }
            }
            Section {
                field("Endpoint", text: $endpoint, prompt: defaults.endpoint.absoluteString) { settings.setEndpointOverride($0) }
                field("Transcription", text: $transcribeModel, prompt: defaults.transcribeModel) { settings.setTranscribeModelOverride($0) }
                field("Live", text: $liveModel, prompt: defaults.liveModel) { settings.setLiveModelOverride($0) }
                field("Formatting", text: $cleanupModel, prompt: defaults.cleanupModel) { settings.setCleanupModelOverride($0) }
            } header: { SettingsSectionHeader("Model overrides") }
            Section {
                Toggle("Use the previous transcription endpoint", isOn: $legacyEndpoint)
                    .onChange(of: legacyEndpoint) { _, value in settings.setLegacyTranscribeEndpoint(value) }
            }
        }
        .settingsPage(title: "Advanced", keyboard: true)
    }

    private func field(_ label: String, text: Binding<String>, prompt: String, save: @escaping (String?) -> Void) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(label).font(Theme.Fonts.caption()).foregroundStyle(Theme.Colors.muted)
            TextField("", text: text, prompt: Text(prompt))
                .textInputAutocapitalization(.never).autocorrectionDisabled().font(Theme.Fonts.code)
                .padding(Theme.Spacing.m)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.field).fill(Theme.Colors.surfaceNested))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.field).strokeBorder(Theme.Colors.hairline, lineWidth: 0.5))
                .onChange(of: text.wrappedValue) { _, value in
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    save(trimmed.isEmpty ? nil : trimmed)
                }
        }
        .padding(.vertical, Theme.Spacing.xs)
    }
}

private struct SettingsSectionHeader: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { GroupLabel(text: text) }
}

private extension View {
    func settingsPage(title: String, keyboard: Bool = false) -> some View {
        self
            .listStyle(.insetGrouped)
            .themedBackground()
            .listRowBackground(Theme.Colors.surface)
            .font(Theme.Fonts.body())
            .tint(Theme.Colors.accent)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .modifier(SettingsKeyboardModifier(enabled: keyboard))
    }
}

private struct SettingsKeyboardModifier: ViewModifier {
    let enabled: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if enabled { content.keyboardDismissable() } else { content }
    }
}


/// The keeper and background-start events from `SessionDiagnostics`.
private struct SessionLogView: View {
    @State private var text = SessionDiagnostics.read()

    var body: some View {
        ScrollView {
            Text(text.isEmpty ? "No events yet." : text)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Theme.Colors.ink)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.Spacing.page)
        }
        .themedBackground()
        .navigationTitle("Session log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Copy") { UIPasteboard.general.string = text }
            }
            ToolbarItem(placement: .topBarLeading) {
                Button("Clear") { SessionDiagnostics.clear(); text = "" }
            }
        }
        .onAppear { text = SessionDiagnostics.read() }
    }
}
