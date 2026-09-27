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

#if os(iOS)
import ActivityKit
import AppIntents
import Foundation

/// The Live Activity shown in the Dynamic Island while a voice session is up.
public struct VoiceSessionAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public enum Phase: String, Codable, Hashable, Sendable {
            case ready
            case recording
            case processing
            case meeting
        }

        public var phase: Phase
        public var mode: KeyboardMode
        /// Start of the current recording or meeting, for the running timer.
        public var since: Date?

        public init(phase: Phase, mode: KeyboardMode = .dictate, since: Date? = nil) {
            self.phase = phase
            self.mode = mode
            self.since = since
        }
    }

    public init() {}
}

/// "End" in the Dynamic Island. Ends the background session and turns the mic off.
public struct EndVoiceSessionIntent: LiveActivityIntent {
    public static let title: LocalizedStringResource = "End VoiceiQ Session"
    public static let isDiscoverable = false

    public init() {}

    public func perform() async throws -> some IntentResult {
        SharedStore.shared.request(.endSession)
        return .result()
    }
}

/// "Stop" in the Dynamic Island while dictating. The result waits for the keyboard.
public struct StopDictationIntent: LiveActivityIntent {
    public static let title: LocalizedStringResource = "Stop Dictation"
    public static let isDiscoverable = false

    public init() {}

    public func perform() async throws -> some IntentResult {
        SharedStore.shared.request(.stopDictation)
        return .result()
    }
}

/// "Stop" in the Dynamic Island while recording a meeting.
public struct StopMeetingIntent: LiveActivityIntent {
    public static let title: LocalizedStringResource = "Stop Meeting Recording"
    public static let isDiscoverable = false

    public init() {}

    public func perform() async throws -> some IntentResult {
        SharedStore.shared.request(.stopMeeting)
        return .result()
    }
}
#endif
