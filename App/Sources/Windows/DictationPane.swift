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

import VoiceIQCore
import SwiftUI

// MARK: - Dictation

struct DictationPane: View {
    private let settings = SettingsStore()
    @State private var sounds = SettingsStore().soundsEnabled
    @State private var smartTranscription = SettingsStore().smartTranscriptionEnabled
    @State private var cleanupPass = SettingsStore().smartCleanupPassEnabled
    @State private var instructions = SettingsStore().customInstructions
    @State private var autoLearn = SettingsStore().autoLearnEnabled
    @State private var meetingDetection = SettingsStore().meetingDetectionEnabled
    @State private var showIdleDot = SettingsStore().showIdleIndicator
    @State private var noiseHandling = SettingsStore().experimentalNoiseHandling
    @State private var liveTranscription = SettingsStore().liveTranscription
    @State private var translationTarget = SettingsStore().translationTargetLanguage
    @State private var showingLanguages = false
    @State private var muteOtherAudio = SettingsStore().muteOtherAudioWhileDictating
    @State private var screenContext = SettingsStore().screenContextEnabled
    @State private var preferredMicrophone = SettingsStore().preferredInputDeviceUID
    @State private var microphones = AudioInputDevices.list()

    var body: some View {
        Form {
            DictationKeySection()
            PermissionsSection()

            Section("Shortcuts") {
                ShortcutRecorderRow(action: .pasteLastTranscript)
                ShortcutRecorderRow(action: .askAnything)
                ShortcutRecorderRow(action: .translate)
                ShortcutRecorderRow(action: .meetingToggle)
                LabeledContent("Translation language") {
                    Button(translationTarget) { showingLanguages.toggle() }
                        .popover(isPresented: $showingLanguages, arrowEdge: .trailing) {
                            LanguagePicker(selected: $translationTarget) {
                                settings.setTranslationTargetLanguage(translationTarget)
                                showingLanguages = false
                            }
                        }
                }
            }

            Section {
                Picker("Microphone", selection: $preferredMicrophone) {
                    Text("System default").tag(String?.none)
                    ForEach(microphones) { device in
                        Text(device.name).tag(Optional(device.uid))
                    }
                }
                .onChange(of: preferredMicrophone) { _, uid in
                    settings.setPreferredInputDeviceUID(uid)
                }
                Toggle("Mute other audio while dictating", isOn: $muteOtherAudio)
                    .onChange(of: muteOtherAudio) { _, enabled in
                        settings.setMuteOtherAudioWhileDictating(enabled)
                    }
            }

            Section {
                Toggle("Sounds", isOn: $sounds)
                    .onChange(of: sounds) { _, enabled in settings.setSoundsEnabled(enabled) }
                Toggle("Show resting indicator", isOn: $showIdleDot)
                    .onChange(of: showIdleDot) { _, show in settings.setShowIdleIndicator(show) }
            } footer: {
                Text("The resting dot grows into a Dictate button on hover; click it for hands-free. Off = the pill appears only while dictating.")
            }

            Section {
                Toggle("Smart transcription", isOn: $smartTranscription)
                    .onChange(of: smartTranscription) { _, enabled in
                        settings.setSmartTranscription(enabled)
                    }
            } footer: {
                Text("Removes filler words and applies self-corrections (\"at 2 — actually 3\") as it transcribes. Off = word for word — unless writing rules below are on, which rewrite either way.")
            }

            Section {
                Toggle("Apply writing rules", isOn: $cleanupPass)
                    .onChange(of: cleanupPass) { _, enabled in
                        guard enabled != settings.smartCleanupPassEnabled else { return }
                        settings.setSmartCleanupPass(enabled)
                    }
                TextEditor(text: $instructions)
                    .font(.body)
                    .frame(minHeight: 180, maxHeight: 320)
                    .disabled(!cleanupPass)
                    .onChange(of: instructions) { _, text in
                        guard text != settings.customInstructions else { return }
                        settings.setCustomInstructions(text)
                    }
                HStack {
                    Spacer()
                    Button("Reset to defaults") {
                        settings.setCustomInstructions(nil)
                        instructions = settings.customInstructions
                    }
                    .disabled(settings.customInstructionsOverride == nil)
                }
            } header: {
                Text("Writing rules")
            } footer: {
                Text("A second model rewrites the transcript by these rules: corrections you speak later fix what you said earlier, sentences are split by grammar rather than pauses, and the layout follows what you said: a message stays a message, several requests become a numbered list.")
            }

            Section {
                Toggle("Learn from your edits", isOn: $autoLearn)
                    .onChange(of: autoLearn) { _, enabled in settings.setAutoLearn(enabled) }
                Toggle("Screen context", isOn: $screenContext)
                    .onChange(of: screenContext) { _, enabled in
                        guard enabled != settings.screenContextEnabled else { return }
                        settings.setScreenContextEnabled(enabled)
                    }
                Toggle("Offer to record calls", isOn: $meetingDetection)
                    .onChange(of: meetingDetection) { _, enabled in settings.setMeetingDetection(enabled) }
            } footer: {
                Text("Words you change after a dictation lands are added to the Dictionary. Screen context sends a snapshot of what you're looking at, taken when dictation starts and when you switch apps, so names and paths on screen are spelled right. When a call app or a meeting tab is using the microphone, the pill asks before recording; the Meeting recording shortcut starts and stops a recording at any time. Notes appear under Meetings.")
            }

            Section {
                Toggle("Better hearing in loud rooms", isOn: $noiseHandling)
                    .onChange(of: noiseHandling) { _, enabled in
                        settings.setExperimentalNoiseHandling(enabled)
                    }
                Toggle("Live transcription", isOn: $liveTranscription)
                    .onChange(of: liveTranscription) { _, enabled in
                        settings.setLiveTranscription(enabled)
                        // Switching it on is an explicit "try again" — clear the
                        // streak that suppressed it, but keep the history so the
                        // footer still tells the truth about how it has gone.
                        if enabled { LiveStats().clearStreak() }
                    }
                    // The legacy transport is a different endpoint entirely, so
                    // live cannot run alongside it. Disabling the control says so;
                    // leaving it tappable but inert is the exact silent no-op this
                    // app keeps writing comments about.
                    .disabled(settings.usesLegacyTranscribeEndpoint || !settings.liveTranscriptionSupported)
            } header: {
                Text("Experimental")
            } footer: {
                if settings.usesLegacyTranscribeEndpoint {
                    Text("Live transcription is unavailable while the legacy transcription endpoint is on in Advanced.")
                } else if !settings.liveTranscriptionSupported {
                    Text("Live transcription needs the provider's own API key or ElevenLabs transcription; it is unavailable through a gateway.")
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Live streams your voice as you speak instead of uploading at the end. On Gemini it uses a separate model with a small daily request quota on free keys. If the connection stumbles it falls back to the normal upload, so nothing is lost. Loud rooms judges your voice against the actual room noise instead of a fixed level.")
                        // Live failing is invisible by design — it just looks like
                        // a slower dictation — so without this the question "is it
                        // actually working?" has no answer.
                        if let summary = LiveStats().summary {
                            Text(summary)
                        }
                    }
                }
            }
        }
        .onAppear { microphones = AudioInputDevices.list() }
        .onReceive(NotificationCenter.default.publisher(for: .voiceIQInputDevicesChanged).receive(on: RunLoop.main)) { _ in
            microphones = AudioInputDevices.list()
        }
        .onReceive(NotificationCenter.default.publisher(for: .gtSettingDidChange).receive(on: RunLoop.main)) { note in
            switch note.object as? String {
            case "smartTranscription": smartTranscription = settings.smartTranscriptionEnabled
            case "liveTranscription": liveTranscription = settings.liveTranscription
            case "smartCleanupPass": cleanupPass = settings.smartCleanupPassEnabled
            case "customInstructions": instructions = settings.customInstructions
            case "autoLearn": autoLearn = settings.autoLearnEnabled
            case "meetingDetection": meetingDetection = settings.meetingDetectionEnabled
            // voiceiq://set drives this headlessly in DEBUG — the pane must not show
            // a stale toggle after the flag moved underneath it.
            case "experimentalNoiseHandling": noiseHandling = settings.experimentalNoiseHandling
            case "translationTargetLanguage": translationTarget = settings.translationTargetLanguage
            case "muteOtherAudioWhileDictating": muteOtherAudio = settings.muteOtherAudioWhileDictating
            case "screenContextEnabled": screenContext = settings.screenContextEnabled
            case "preferredInputDeviceUID": preferredMicrophone = settings.preferredInputDeviceUID
            default: break
            }
        }
    }
}

private struct LanguagePicker: View {
    @Binding var selected: String
    let onSelect: () -> Void
    @State private var search = ""

    private var languages: [GeminiLanguage] {
        guard !search.isEmpty else { return GeminiLanguages.supported }
        return GeminiLanguages.supported.filter {
            $0.name.localizedCaseInsensitiveContains(search)
                || $0.code.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Search languages", text: $search)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.leading)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(languages) { language in
                        Button {
                            selected = language.name
                            onSelect()
                        } label: {
                            Text(language.name)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(
                                    RoundedRectangle(cornerRadius: VoiceIQUI.Radius.small)
                                        .fill(language.name == selected
                                              ? Color.primary.opacity(VoiceIQUI.StateLayer.hover) : .clear)
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .padding(12)
        .frame(width: 280, height: 360)
    }
}
