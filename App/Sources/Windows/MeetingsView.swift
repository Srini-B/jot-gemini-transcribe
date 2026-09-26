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

import AppKit
import VoiceIQCore
import SwiftUI

struct MeetingsPane: View {
    @ObservedObject var engine: MeetingEngine
    let store: MeetingStore
    @State private var meetings: [MeetingMeta] = []
    @State private var selection: MeetingID?
    @State private var tab = 0
    @State private var notes: MeetingNotes?
    @State private var transcript: [TranscriptSegment] = []

    var body: some View {
        HStack(spacing: 0) {
            List(meetings, selection: $selection) { meeting in
                VStack(alignment: .leading, spacing: 3) {
                    Text(title(meeting)).font(VoiceIQUI.TypeScale.body()).lineLimit(1)
                    Text(timeRange(meeting)).font(VoiceIQUI.TypeScale.labelSmall()).foregroundStyle(.secondary)
                    Text("\(duration(meeting.durationSeconds)) · \(status(meeting.status))").font(VoiceIQUI.TypeScale.labelSmall()).foregroundStyle(.secondary)
                }.tag(meeting.id)
            }
            .overlay { if meetings.isEmpty { Text("No meetings yet").foregroundStyle(.secondary) } }
            .frame(width: 230)
            Divider()
            VStack(spacing: 0) {
                toolbar
                if let meeting = selected { detail(meeting) } else { ContentUnavailableView("No Meeting Selected", systemImage: "person.2").frame(maxHeight: .infinity) }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear(perform: reload)
        .onChange(of: selection) { _, _ in loadSelection() }
        .onChange(of: engine.phase) { _, phase in if phase == .idle { reload() } }
    }

    private var toolbar: some View {
        HStack {
            Button(recording ? "Stop" : "Record", systemImage: recording ? "stop.fill" : "record.circle") {
                recording ? engine.stopRecording() : engine.startRecording()
            }
            Spacer()
            Button("Export", systemImage: "square.and.arrow.up") { export() }.disabled(selection == nil)
            Button("Delete", systemImage: "trash", role: .destructive) { remove() }.disabled(selection == nil)
        }
        .padding(.horizontal, VoiceIQUI.Spacing.l)
        .padding(.top, VoiceIQUI.Spacing.l)
        .padding(.bottom, VoiceIQUI.Spacing.s)
    }

    private func detail(_ meeting: MeetingMeta) -> some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) { Text("Notes").tag(0); Text("Transcript").tag(1) }
                .pickerStyle(.segmented).labelsHidden().padding(.horizontal, VoiceIQUI.Spacing.l)
            ScrollView { if tab == 0 { notesView } else { transcriptView(meeting) } }.padding(VoiceIQUI.Spacing.l)
        }
    }

    private var notesView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(notes?.title ?? "Meeting").font(VoiceIQUI.TypeScale.title())
            section("Summary", notes.map { [$0.summary] } ?? [])
            section("Decisions", notes?.decisions ?? [])
            if let actions = notes?.actions, !actions.isEmpty {
                VStack(alignment: .leading, spacing: 8) { Text("Action items").font(VoiceIQUI.TypeScale.labelSmall()).foregroundStyle(.secondary); ForEach(Array(actions.enumerated()), id: \.offset) { _, item in Text("• \(item.text)\(actionSuffix(item))") } }
            }
            section("Notes", notes?.notes ?? [])
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func transcriptView(_ meeting: MeetingMeta) -> some View {
        LazyVStack(alignment: .leading, spacing: 14) {
            ForEach(Array(transcript.enumerated()), id: \.offset) { _, segment in
                HStack(alignment: .top, spacing: 10) {
                    SpeakerName(label: segment.speaker, name: meeting.speakerNames[segment.speaker]) { name in try? store.renameSpeaker(id: meeting.id, label: segment.speaker, name: name); reload() }
                    Text(segment.text).textSelection(.enabled)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func section(_ title: String, _ items: [String]) -> some View {
        Group { if !items.isEmpty { VStack(alignment: .leading, spacing: 8) { Text(title).font(VoiceIQUI.TypeScale.labelSmall()).foregroundStyle(.secondary); ForEach(items, id: \.self) { Text(items.count == 1 ? $0 : "• \($0)") } } } }
    }
    private var selected: MeetingMeta? { meetings.first { $0.id == selection } }
    private var recording: Bool { if case .recording = engine.phase { return true }; return false }
    private func reload() { meetings = store.list(); if selection == nil { selection = meetings.first?.id }; loadSelection() }
    private func loadSelection() { guard let id = selection else { return }; notes = try? store.loadNotes(id: id); transcript = (try? store.loadTranscript(id: id)) ?? [] }
    private func remove() { guard let id = selection else { return }; try? store.delete(id: id); selection = nil; reload() }
    private func export() { guard let id = selection, let folder = store.folder(for: id) else { return }; _ = try? store.exportMarkdown(id: id); NSWorkspace.shared.activateFileViewerSelecting([folder.appendingPathComponent("notes.md")]) }
    private func title(_ meeting: MeetingMeta) -> String {
        if let title = meeting.title, !title.isEmpty { return title }
        return meeting.startedAt.formatted(date: .abbreviated, time: .shortened)
    }
    /// "26 Sep 2026, 2:23 – 2:24 PM", the same shape as a dictation's timestamp
    /// plus the end time; a recording still in progress shows only its start.
    private func timeRange(_ meeting: MeetingMeta) -> String {
        let start = meeting.startedAt.formatted(date: .abbreviated, time: .shortened)
        guard let end = meeting.endedAt else { return start }
        let sameDay = Calendar.current.isDate(meeting.startedAt, inSameDayAs: end)
        return "\(start) – \(end.formatted(date: sameDay ? .omitted : .abbreviated, time: .shortened))"
    }
    private func duration(_ seconds: Double) -> String { seconds < 60 ? "\(Int(seconds))s" : "\(Int(seconds / 60))m" }
    private func status(_ value: MeetingStatus) -> String { switch value { case .recording: "Recording"; case .transcribing: "Transcribing"; case .summarizing: "Summarizing"; case .done: "Done"; case .failed: "Failed" } }
    private func actionSuffix(_ item: ActionItem) -> String { let values = [item.owner, item.deadline].compactMap { $0 }; return values.isEmpty ? "" : " · " + values.joined(separator: " · ") }
}

private struct SpeakerName: View {
    let label: String, name: String?
    let save: (String) -> Void
    @State private var editing = false
    @State private var draft = ""
    var body: some View {
        Button(name ?? label) { draft = name ?? ""; editing = true }.buttonStyle(.borderless).font(.caption.bold()).frame(width: 80, alignment: .leading)
            .popover(isPresented: $editing) { HStack { TextField("Name", text: $draft).onSubmit { save(draft); editing = false }; Button("Save") { save(draft); editing = false } }.padding().frame(width: 220) }
    }
}
