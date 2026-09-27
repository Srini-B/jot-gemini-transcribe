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

import ActivityKit
import AppIntents
import SwiftUI
import VoiceIQBridge
import WidgetKit

@main
struct VoiceIQWidgets: WidgetBundle {
    var body: some Widget {
        VoiceSessionLiveActivity()
    }
}

private let accent = Color(red: 0.341, green: 0.525, blue: 0.941)
private let recordingRed = Color(red: 0.92, green: 0.26, blue: 0.21)

struct VoiceSessionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: VoiceSessionAttributes.self) { context in
            LockScreenView(state: context.state)
                .padding(16)
                .activityBackgroundTint(Color.black.opacity(0.8))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    PhaseIcon(phase: context.state.phase)
                        .font(.title2)
                        .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ElapsedText(state: context.state)
                        .font(.title3.monospacedDigit())
                        .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(title(for: context.state))
                        .font(.headline)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ActionButtons(state: context.state)
                        .padding(.top, 4)
                }
            } compactLeading: {
                PhaseIcon(phase: context.state.phase)
            } compactTrailing: {
                ElapsedText(state: context.state)
                    .font(.caption2.monospacedDigit())
                    .frame(maxWidth: 44)
            } minimal: {
                PhaseIcon(phase: context.state.phase)
            }
            .keylineTint(context.state.phase == .recording || context.state.phase == .meeting ? recordingRed : accent)
        }
    }
}

private func title(for state: VoiceSessionAttributes.ContentState) -> String {
    switch state.phase {
    case .ready: return "VoiceiQ ready"
    case .recording: return "Listening"
    case .processing: return state.mode == .ask ? "Thinking" : "Writing"
    case .meeting: return "Recording meeting"
    }
}

private struct PhaseIcon: View {
    let phase: VoiceSessionAttributes.ContentState.Phase

    var body: some View {
        switch phase {
        case .ready:
            Image(systemName: "mic.fill").foregroundStyle(accent)
        case .recording:
            Image(systemName: "waveform").foregroundStyle(recordingRed)
        case .processing:
            Image(systemName: "ellipsis").foregroundStyle(accent)
        case .meeting:
            Image(systemName: "record.circle").foregroundStyle(recordingRed)
        }
    }
}

private struct ElapsedText: View {
    let state: VoiceSessionAttributes.ContentState

    var body: some View {
        if let since = state.since, state.phase == .recording || state.phase == .meeting {
            Text(timerInterval: since...Date.distantFuture, countsDown: false)
                .multilineTextAlignment(.trailing)
        } else if state.phase == .ready {
            Text("Ready").foregroundStyle(.secondary)
        } else {
            Text("")
        }
    }
}

private struct ActionButtons: View {
    let state: VoiceSessionAttributes.ContentState

    var body: some View {
        HStack(spacing: 12) {
            switch state.phase {
            case .recording:
                Button(intent: StopDictationIntent()) {
                    Label("Stop", systemImage: "stop.fill").frame(maxWidth: .infinity)
                }
                .tint(recordingRed)
            case .meeting:
                Button(intent: StopMeetingIntent()) {
                    Label("Stop", systemImage: "stop.fill").frame(maxWidth: .infinity)
                }
                .tint(recordingRed)
            case .ready, .processing:
                Button(intent: EndVoiceSessionIntent()) {
                    Label("End session", systemImage: "xmark").frame(maxWidth: .infinity)
                }
                .tint(.gray)
            }
        }
        .buttonStyle(.borderedProminent)
    }
}

private struct LockScreenView: View {
    let state: VoiceSessionAttributes.ContentState

    var body: some View {
        HStack(spacing: 12) {
            PhaseIcon(phase: state.phase).font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title(for: state)).font(.headline).foregroundStyle(.white)
                ElapsedText(state: state).font(.subheadline.monospacedDigit()).foregroundStyle(.white.opacity(0.7))
            }
            Spacer()
            ActionButtons(state: state).frame(width: 150)
        }
    }
}
