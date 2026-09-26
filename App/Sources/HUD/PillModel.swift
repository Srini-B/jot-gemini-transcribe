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

/// The pill's semantic state — a pure projection of coordinator state
/// (experience spec owns all timing/lifecycle; critic reconciliation #7).
enum PillState: Equatable {
    case hidden
    case idleDot
    case listening(locked: Bool)
    case processing
    case success(words: Int?)
    /// Neutral informational chip (coaching hint, copied-to-clipboard, offline…).
    case notice(String)
    case answer(String)
    /// Error styling: errorContainer surface + "saved to History" framing.
    case error(String)
    /// A call was noticed; the pill offers to record it. The string names the app or site.
    case meetingPrompt(String)
    /// A meeting is recording: timer, waveform, live preview, stop.
    case meetingRecording(since: Date)
}

/// Microphone level for the waveform. A plain reference, not published: the
/// level arrives ~30 times a second, and publishing it rebuilt the whole pill
/// view and re-laid out its hosting view on every tick. The waveform's Canvas
/// reads the latest value on its own timeline instead.
@MainActor
final class LevelSource {
    var value: Float = 0

    static let silent = LevelSource()
}

@MainActor
final class PillModel: ObservableObject {
    @Published var state: PillState = .idleDot
    @Published var elapsed: TimeInterval = 0
    /// Still-working slow state (>3s in processing — TimeoutPolicy.slowStateUI).
    @Published var slow = false
    /// Live mode's speculative transcript, shown while the user speaks. Display
    /// only: this is a guess the model is still revising, and it is never what
    /// gets inserted.
    @Published var partial: String = ""
    /// Meeting live preview. Separate from `partial`, which dictation clears on
    /// every begin and would wipe the meeting text mid-call.
    @Published var meetingPreview: String = ""
    let level = LevelSource()
}
