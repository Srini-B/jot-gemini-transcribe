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

/// Four steps: key, microphone, keyboard, try it.
struct OnboardingView: View {
    let onFinished: () -> Void
    @State private var step = Step.welcome
    @State private var status = SetupStatus.current()
    @State private var tryText = ""
    @Environment(\.scenePhase) private var scenePhase

    enum Step: Int, CaseIterable { case welcome, key, microphone, keyboard, tryIt }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                ProgressView(value: Double(step.rawValue), total: Double(Step.allCases.count - 1))
                    .padding(.horizontal)
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.horizontal, 24)
                footer
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
            }
            .padding(.top, 12)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { status = SetupStatus.current() }
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .welcome:
            VStack(spacing: 16) {
                Spacer()
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 88))
                    .foregroundStyle(Brand.accent)
                Text("VoiceiQ").font(.largeTitle.bold())
                Text("Tap the mic. Speak. It types.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        case .key:
            VStack(alignment: .leading, spacing: 16) {
                Text("Add your API key").font(.title.bold())
                KeyForm(provider: .gemini) { status = SetupStatus.current() }
                NavigationLink("Use OpenRouter or Vercel instead") { KeysView() }
                    .font(.subheadline)
            }
        case .microphone:
            VStack(alignment: .leading, spacing: 16) {
                Text("Allow the microphone").font(.title.bold())
                SetupRow(title: "Microphone", done: status.micGranted)
            }
        case .keyboard:
            VStack(alignment: .leading, spacing: 16) {
                Text("Add the keyboard").font(.title.bold())
                KeyboardSetupSteps(status: status)
            }
        case .tryIt:
            VStack(alignment: .leading, spacing: 16) {
                Text("Try it").font(.title.bold())
                TextField("Switch to the VoiceiQ keyboard and tap the mic", text: $tryText, axis: .vertical)
                    .lineLimit(4...10)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    @ViewBuilder private var footer: some View {
        switch step {
        case .microphone where !status.micGranted:
            primary("Allow") {
                AVAudioApplication.requestRecordPermission { granted in
                    Task { @MainActor in
                        status = SetupStatus.current()
                        if granted { advance() }
                    }
                }
            }
        case .keyboard where !(status.keyboardAdded && status.fullAccess):
            VStack(spacing: 10) {
                primary("Open Settings") {
                    UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                }
                Button("Later", action: advance)
            }
        case .key where !status.hasKey:
            Button("Later", action: advance)
        case .tryIt:
            primary("Done", action: onFinished)
        default:
            primary("Continue", action: advance)
        }
    }

    private func primary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
    }

    private func advance() {
        status = SetupStatus.current()
        if let next = Step(rawValue: step.rawValue + 1) {
            withAnimation { step = next }
        }
    }
}

/// The Settings path, with live checks for each part.
struct KeyboardSetupSteps: View {
    let status: SetupStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Settings › VoiceiQ › Keyboards")
                .font(.body.weight(.medium))
            SetupRow(title: "Turn on VoiceiQ", done: status.keyboardAdded)
            SetupRow(title: "Turn on Allow Full Access", done: status.fullAccess)
            if status.keyboardAdded && !status.fullAccess {
                Text("Then open the VoiceiQ keyboard once in any app.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct KeyboardSetupView: View {
    @State private var status = SetupStatus.current()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Form {
            Section {
                KeyboardSetupSteps(status: status)
                    .padding(.vertical, 6)
            }
            Section {
                Button("Open Settings") {
                    UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                }
            }
        }
        .navigationTitle("Keyboard")
        .onChange(of: scenePhase) { _, phase in if phase == .active { status = SetupStatus.current() } }
        .onAppear { status = SetupStatus.current() }
    }
}
