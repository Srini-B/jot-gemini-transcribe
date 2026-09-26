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

import Foundation

public enum CallSource: Equatable, Sendable, Codable {
    case app(bundleID: String, name: String)
    case browser(bundleID: String, host: String)
}

public enum MeetingPhase: Equatable, Sendable {
    case idle
    case callDetected(CallSource)
    case recording(MeetingID, since: Date)
    case processing(MeetingID)
    case failed(MeetingID, String)
}

public struct MeetingID: Hashable, Codable, Sendable, Identifiable {
    public let uuid: UUID
    public var id: UUID { uuid }
    public init(uuid: UUID = UUID()) { self.uuid = uuid }
}

public struct TranscriptSegment: Codable, Equatable, Sendable {
    public var speaker: String
    public var text: String
    public var chunkIndex: Int
    public init(speaker: String, text: String, chunkIndex: Int) {
        self.speaker = speaker; self.text = text; self.chunkIndex = chunkIndex
    }
}

public struct ActionItem: Codable, Equatable, Sendable {
    public var text: String
    public var owner: String?
    public var deadline: String?
    public init(text: String, owner: String? = nil, deadline: String? = nil) {
        self.text = text; self.owner = owner; self.deadline = deadline
    }
}

public struct MeetingNotes: Codable, Equatable, Sendable {
    public var title: String
    public var summary: String
    public var decisions: [String]
    public var actions: [ActionItem]
    public var notes: [String]
    public init(title: String, summary: String, decisions: [String], actions: [ActionItem], notes: [String]) {
        self.title = title; self.summary = summary; self.decisions = decisions; self.actions = actions; self.notes = notes
    }
}

public enum MeetingStatus: Codable, Equatable, Sendable {
    case recording, transcribing, summarizing, done
    case failed(String)
}

public struct MeetingMeta: Codable, Equatable, Sendable, Identifiable {
    public var id: MeetingID
    public var startedAt: Date
    public var endedAt: Date?
    public var source: CallSource?
    public var durationSeconds: Double
    public var status: MeetingStatus
    public var speakerNames: [String: String]
    public var title: String?

    public init(id: MeetingID, startedAt: Date, endedAt: Date? = nil, source: CallSource? = nil,
                durationSeconds: Double = 0, status: MeetingStatus = .recording,
                speakerNames: [String: String] = [:], title: String? = nil) {
        self.id = id; self.startedAt = startedAt; self.endedAt = endedAt; self.source = source
        self.durationSeconds = durationSeconds; self.status = status; self.speakerNames = speakerNames; self.title = title
    }
}
