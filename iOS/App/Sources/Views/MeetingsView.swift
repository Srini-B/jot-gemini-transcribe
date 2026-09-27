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
import VoiceIQCore

/// A recorder: start, the phone records the room, stop, notes are made.
struct MeetingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var meetings: [MeetingMeta] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    RecorderCard(meetings: model.meetings)
                }
                Section {
                    ForEach(meetings) { meta in
                        NavigationLink { MeetingDetail(meta: meta) } label: { MeetingRow(meta: meta) }
                    }
                    .onDelete { offsets in
                        for index in offsets { try? model.meetings.store.delete(id: meetings[index].id) }
                        reload()
                    }
                }
            }
            .navigationTitle("Meetings")
            .onAppear(perform: reload)
            .onReceive(model.meetings.$phase) { _ in reload() }
        }
    }

    private func reload() {
        meetings = model.meetings.store.list().sorted { $0.startedAt > $1.startedAt }
    }
}

private struct RecorderCard: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var meetings: MeetingEngine

    var body: some View {
        let phase = meetings.phase
        VStack(spacing: 14) {
            switch phase {
            case let .recording(_, since):
                Text(timerInterval: since...Date.distantFuture, countsDown: false)
                    .font(.system(size: 44, weight: .light, design: .rounded).monospacedDigit())
                Button(action: model.stopMeeting) {
                    Label("Stop", systemImage: "stop.fill").frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(Brand.recording)
            case .processing:
                ProgressView("Making notes")
                    .padding(.vertical, 8)
            default:
                Button(action: model.startMeeting) {
                    Label("Record meeting", systemImage: "record.circle").frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(Brand.recording)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

private struct MeetingRow: View {
    let meta: MeetingMeta

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(meta.title ?? "Meeting").lineLimit(1)
            HStack(spacing: 6) {
                Text(meta.startedAt, format: .dateTime.month().day().hour().minute())
                Text("· \(Duration.seconds(meta.durationSeconds).formatted(.time(pattern: .minuteSecond)))")
                switch meta.status {
                case .done: EmptyView()
                case .failed: Text("· Failed").foregroundStyle(Brand.recording)
                default: Text("· Processing")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

private struct MeetingDetail: View {
    @EnvironmentObject private var model: AppModel
    let meta: MeetingMeta
    @State private var notes: MeetingNotes?
    @State private var transcript: [TranscriptSegment] = []
    @State private var markdown: String?

    var body: some View {
        List {
            if let notes {
                Section {
                    if let kind = notes.type.flatMap(MeetingKind.init(rawValue:)), kind != .general {
                        Text(kind.displayName).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(notes.summary)
                }
                ForEach(Array((notes.sections ?? []).enumerated()), id: \.offset) { _, part in
                    if !part.items.isEmpty {
                        Section(part.title) { ForEach(part.items, id: \.self) { Text($0) } }
                    }
                }
                if !notes.decisions.isEmpty {
                    Section("Decisions") { ForEach(notes.decisions, id: \.self) { Text($0) } }
                }
                if !notes.actions.isEmpty {
                    Section("Action items") {
                        ForEach(notes.actions, id: \.text) { action in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(action.text)
                                let detail = [action.owner, action.deadline].compactMap { $0 }.joined(separator: " · ")
                                if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
                if !notes.notes.isEmpty {
                    Section("Notes") { ForEach(notes.notes, id: \.self) { Text($0) } }
                }
            } else if case .failed(let reason) = meta.status {
                Section {
                    Text(reason).foregroundStyle(.secondary)
                    Button("Retry") { model.meetings.retry(id: meta.id) }
                }
            } else {
                Section { ProgressView("Making notes") }
            }
            if !transcript.isEmpty {
                Section("Transcript") {
                    ForEach(Array(transcript.enumerated()), id: \.offset) { _, segment in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(MeetingSpeaker.displayName(segment.speaker, names: meta.speakerNames, suggested: notes?.speakers))
                                    .font(.caption.bold())
                                    .foregroundStyle(Brand.accent)
                                if let start = segment.start {
                                    Text(MeetingNotesPrompt.clock(start)).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Text(segment.text)
                        }
                    }
                }
            }
        }
        .navigationTitle(notes?.title ?? meta.title ?? "Meeting")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if meta.status == .done {
                Menu {
                    Button("Notes") { model.meetings.regenerateNotes(id: meta.id) }.disabled(transcript.isEmpty)
                    Button("Transcript and notes") { model.meetings.retry(id: meta.id) }
                } label: { Label("Redo", systemImage: "arrow.clockwise") }
                    .disabled(model.meetings.phase != .idle)
            }
            if let markdown {
                ShareLink(item: markdown)
            }
        }
        .onAppear(perform: load)
        .onReceive(model.meetings.$phase) { phase in if phase == .idle { load() } }
    }

    private func load() {
        notes = try? model.meetings.store.loadNotes(id: meta.id)
        transcript = (try? model.meetings.store.loadTranscript(id: meta.id)) ?? []
        markdown = try? model.meetings.store.exportMarkdown(id: meta.id)
    }
}
