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
                    Text(durationLine(meeting)).font(VoiceIQUI.TypeScale.labelSmall()).foregroundStyle(.secondary)
                }.tag(meeting.id)
            }
            .overlay { if meetings.isEmpty { Text("No meetings yet").foregroundStyle(.secondary) } }
            .frame(width: 230)
            // Same as the main sidebar: Divider() stops below the transparent
            // titlebar, a rectangle reaches the top edge.
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(width: 1)
                .ignoresSafeArea(.container, edges: .top)
            VStack(spacing: 0) {
                toolbar
                if let meeting = selected { detail(meeting) } else { ContentUnavailableView("No Meeting Selected", systemImage: "person.2").frame(maxHeight: .infinity) }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear(perform: reload)
        .onChange(of: selection) { _, _ in loadSelection() }
        .onChange(of: engine.phase) { _, _ in reload() }
    }

    private var toolbar: some View {
        HStack {
            Button(recording ? "Stop" : "Record", systemImage: recording ? "stop.fill" : "record.circle") {
                recording ? engine.stopRecording() : engine.startRecording()
            }
            Spacer()
            if let meeting = selected, case .failed = meeting.status {
                Button("Retry", systemImage: "arrow.clockwise") { engine.retry(id: meeting.id) }
                    .disabled(engine.phase != .idle)
            } else if let meeting = selected, meeting.status == .done {
                Menu {
                    Button("Notes") { engine.regenerateNotes(id: meeting.id) }.disabled(transcript.isEmpty)
                    Button("Transcript and notes") { engine.retry(id: meeting.id) }
                } label: { Label("Redo", systemImage: "arrow.clockwise") }
                    .fixedSize()
                    .disabled(engine.phase != .idle)
            }
            Button("Export", systemImage: "square.and.arrow.up") { export() }.disabled(selection == nil)
            Button("Delete", systemImage: "trash", role: .destructive) { remove() }.disabled(selection == nil)
        }
        .padding(.horizontal, VoiceIQUI.Spacing.l)
        .padding(.top, VoiceIQUI.Spacing.l)
        .padding(.bottom, VoiceIQUI.Spacing.s)
    }

    private func detail(_ meeting: MeetingMeta) -> some View {
        VStack(spacing: 0) {
            if case .failed(let reason) = meeting.status {
                Label(reason, systemImage: "exclamationmark.triangle.fill")
                    .font(VoiceIQUI.TypeScale.body())
                    .foregroundStyle(VoiceIQUI.Colors.error)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(VoiceIQUI.Spacing.m)
                    .background(RoundedRectangle(cornerRadius: VoiceIQUI.Radius.medium).fill(VoiceIQUI.Colors.error.opacity(0.1)))
                    .padding(.horizontal, VoiceIQUI.Spacing.l)
                    .padding(.bottom, VoiceIQUI.Spacing.s)
            }
            Picker("", selection: $tab) { Text("Notes").tag(0); Text("Transcript").tag(1) }
                .pickerStyle(.segmented).labelsHidden().padding(.horizontal, VoiceIQUI.Spacing.l)
            if tab == 0 {
                ScrollView { notesView }.padding(VoiceIQUI.Spacing.l)
            } else {
                transcriptView(meeting).padding(VoiceIQUI.Spacing.l)
            }
        }
    }

    private var notesView: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let kind = notes?.type.flatMap(MeetingKind.init(rawValue:)), kind != .general {
                Text(kind.displayName).font(VoiceIQUI.TypeScale.labelSmall()).foregroundStyle(.secondary)
            }
            Text(notes?.title ?? "Meeting").font(VoiceIQUI.TypeScale.title())
            section("Summary", notes.map { [$0.summary] } ?? [])
            ForEach(Array((notes?.sections ?? []).enumerated()), id: \.offset) { _, part in section(part.title, part.items) }
            section("Decisions", notes?.decisions ?? [])
            if let actions = notes?.actions, !actions.isEmpty {
                VStack(alignment: .leading, spacing: 8) { Text("Action items").font(VoiceIQUI.TypeScale.labelSmall()).foregroundStyle(.secondary); ForEach(Array(actions.enumerated()), id: \.offset) { _, item in Text("• \(item.text)\(actionSuffix(item))") } }
            }
            section("Notes", notes?.notes ?? [])
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One text view for the whole transcript. A SwiftUI Text per segment with
    /// selection enabled froze the window on scroll at twenty minutes of speech.
    private func transcriptView(_ meeting: MeetingMeta) -> some View {
        VStack(alignment: .leading, spacing: VoiceIQUI.Spacing.s) {
            HStack(spacing: VoiceIQUI.Spacing.s) {
                ForEach(speakerLabels, id: \.self) { label in
                    SpeakerName(label: MeetingSpeaker.defaultName(label),
                                name: MeetingSpeaker.displayName(label, names: meeting.speakerNames, suggested: notes?.speakers),
                                evidence: meeting.speakerNames[label] == nil ? suggestion(for: label)?.evidence : nil) { name in
                        try? store.renameSpeaker(id: meeting.id, label: label, name: name); reload()
                    }
                }
            }
            RichTextView(text: transcriptText(meeting))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func suggestion(for label: String) -> SpeakerSuggestion? {
        notes?.speakers?.first { $0.label == MeetingSpeaker.defaultName(label) }
    }

    private var speakerLabels: [String] {
        var seen: [String] = []
        for segment in transcript where !seen.contains(segment.speaker) { seen.append(segment.speaker) }
        return seen
    }

    private func transcriptText(_ meeting: MeetingMeta) -> NSAttributedString {
        let body = GTFont.nsFlex(14, weight: 400)
        let name = GTFont.nsFlex(12, weight: 600)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2
        paragraph.paragraphSpacing = 12
        let nameParagraph = NSMutableParagraphStyle()
        nameParagraph.paragraphSpacing = 2
        let out = NSMutableAttributedString()
        for segment in transcript {
            let speaker = MeetingSpeaker.displayName(segment.speaker, names: meeting.speakerNames, suggested: notes?.speakers)
            let time = segment.start.map { "  " + MeetingNotesPrompt.clock($0) } ?? ""
            out.append(NSAttributedString(string: speaker + time + "\n", attributes: [
                .font: name, .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: nameParagraph,
            ]))
            out.append(NSAttributedString(string: segment.text + "\n", attributes: [
                .font: body, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph,
            ]))
        }
        return out
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
    /// A finished meeting shows only its length; anything still in flight or failed says so.
    private func durationLine(_ meeting: MeetingMeta) -> String {
        let length = duration(meeting.durationSeconds)
        switch meeting.status {
        case .done: return length
        case .recording: return "\(length) · Recording"
        case .transcribing: return "\(length) · Transcribing"
        case .summarizing: return "\(length) · Making notes"
        case .failed: return "\(length) · Failed"
        }
    }
    private func actionSuffix(_ item: ActionItem) -> String { let values = [item.owner, item.deadline].compactMap { $0 }; return values.isEmpty ? "" : " · " + values.joined(separator: " · ") }
}

private struct SpeakerName: View {
    let label: String, name: String
    /// The words that gave a suggested name, shown on hover.
    let evidence: String?
    let save: (String) -> Void
    @State private var editing = false
    @State private var draft = ""
    var body: some View {
        Button(name, systemImage: "pencil") { draft = name == label ? "" : name; editing = true }.buttonStyle(.bordered).controlSize(.small)
            .help(evidence ?? label)
            .popover(isPresented: $editing) { HStack { TextField("Name", text: $draft).onSubmit { save(draft); editing = false }; Button("Save") { save(draft); editing = false } }.padding().frame(width: 220) }
    }
}
