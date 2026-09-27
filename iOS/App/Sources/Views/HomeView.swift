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

import AVFoundation
import SwiftUI
import VoiceIQCore

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: VoiceSession
    @Environment(\.scenePhase) private var scenePhase
    @State private var tryText = ""
    @State private var setup = SetupStatus.current()
    @State private var stats: HistoryStore.Stats?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Circle()
                            .fill(session.isActive ? Color.green : Color.secondary.opacity(0.4))
                            .frame(width: 12, height: 12)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.isActive ? "Voice session on" : "Voice session off")
                                .font(.headline)
                            if !session.isActive {
                                Text("Starts on your first dictation")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button(session.isActive ? "End" : "Start") {
                            session.isActive ? model.endSession() : model.startSession()
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 4)
                }

                if !setup.isComplete {
                    Section("Finish setup") {
                        SetupRows(status: setup)
                    }
                }

                Section("Try it") {
                    TextField("Switch to the VoiceiQ keyboard and tap the mic", text: $tryText, axis: .vertical)
                        .lineLimit(3...8)
                }

                if let stats, stats.totalDictations > 0 {
                    Section {
                        LabeledContent("Words dictated", value: stats.totalWords.formatted())
                        LabeledContent("Dictations", value: stats.totalDictations.formatted())
                        if stats.averageWPM > 0 {
                            LabeledContent("Speaking speed", value: "\(stats.averageWPM) wpm")
                        }
                    }
                }
            }
            .navigationTitle("VoiceiQ")
            .onAppear(perform: refresh)
            .onChange(of: scenePhase) { _, phase in if phase == .active { refresh() } }
        }
    }

    private func refresh() {
        setup = SetupStatus.current()
        stats = model.historyStore?.stats()
    }
}

/// What still blocks dictation, checked fresh each time the screen shows.
struct SetupStatus: Equatable {
    var hasKey: Bool
    var micGranted: Bool
    var keyboardAdded: Bool
    var fullAccess: Bool

    var isComplete: Bool { hasKey && micGranted && keyboardAdded && fullAccess }

    static func current() -> SetupStatus {
        SetupStatus(
            hasKey: KeychainStore.hasModelKey,
            micGranted: AVAudioApplication.shared.recordPermission == .granted,
            keyboardAdded: MobileSettings.keyboardAdded,
            fullAccess: MobileSettings.keyboardHasFullAccess
        )
    }
}

struct SetupRows: View {
    let status: SetupStatus

    var body: some View {
        NavigationLink { KeysView() } label: {
            SetupRow(title: "API key", done: status.hasKey)
        }
        Button {
            AVAudioApplication.requestRecordPermission { _ in }
        } label: {
            SetupRow(title: "Microphone", done: status.micGranted)
        }
        .disabled(status.micGranted)
        NavigationLink { KeyboardSetupView() } label: {
            SetupRow(title: "Keyboard and Full Access", done: status.keyboardAdded && status.fullAccess)
        }
    }
}

struct SetupRow: View {
    let title: String
    let done: Bool

    var body: some View {
        Label {
            Text(title).foregroundStyle(.primary)
        } icon: {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? .green : .secondary)
        }
    }
}
