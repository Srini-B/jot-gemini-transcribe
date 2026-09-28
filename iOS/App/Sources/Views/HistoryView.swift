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

struct HistoryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var records: [DictationRecord] = []
    @State private var search = ""
    @State private var confirmDeleteAll = false

    private var sections: [HistoryDaySection] { HistoryDaySection.group(records) }

    var body: some View {
        NavigationStack {
            List {
                ForEach(sections) { section in
                    Section(section.title) {
                        ForEach(section.records) { record in
                            NavigationLink { HistoryDetail(record: record, reload: reload) } label: {
                                HistoryRow(record: record)
                            }
                        }
                        .onDelete { offsets in delete(offsets, from: section.records) }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .listRowBackground(Theme.Colors.surface)
            .themedBackground()
            .keyboardDismissable()
            .overlay { if records.isEmpty { HistoryEmptyState(isSearching: !search.isEmpty) } }
            .searchable(text: $search)
            .onChange(of: search) { _, _ in reload() }
            .navigationTitle("History")
            .toolbar {
                if !records.isEmpty {
                    Menu {
                        Button("Delete All", role: .destructive) { confirmDeleteAll = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("History actions")
                }
            }
            .confirmationDialog("Delete all history?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
                Button("Delete All", role: .destructive) {
                    model.historyStore?.deleteAll(removeFolders: true, sparing: model.coordinator.activeSessionFolder)
                    model.coordinator.clearLastResult()
                    reload()
                }
            }
            .onAppear(perform: reload)
            .onReceive(NotificationCenter.default.publisher(for: .gtHistoryDidChange).receive(on: RunLoop.main)) { _ in reload() }
        }
    }

    private func delete(_ offsets: IndexSet, from sectionRecords: [DictationRecord]) {
        for index in offsets { model.historyStore?.delete(id: sectionRecords[index].id, removeFolder: true) }
        reload()
    }

    private func reload() {
        records = model.historyStore?.records(matching: search.isEmpty ? nil : search) ?? []
    }
}

private struct HistoryDaySection: Identifiable {
    let day: Date
    let records: [DictationRecord]
    var id: Date { day }

    var title: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(date: .abbreviated, time: .omitted)
    }

    static func group(_ records: [DictationRecord]) -> [HistoryDaySection] {
        let grouped = Dictionary(grouping: records) { Calendar.current.startOfDay(for: $0.startedAt) }
        return grouped.keys.sorted(by: >).map { HistoryDaySection(day: $0, records: grouped[$0] ?? []) }
    }
}

private struct HistoryEmptyState: View {
    let isSearching: Bool

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            IconTile(systemImage: isSearching ? "magnifyingglass" : "waveform", size: 72)
            Text(isSearching ? "No results" : "No dictations yet")
                .font(Theme.Fonts.title2())
                .foregroundStyle(Theme.Colors.ink)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.canvas)
    }
}

private struct HistoryRow: View {
    let record: DictationRecord

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(alignment: .top, spacing: Theme.Spacing.s) {
                Text(record.displayText.isEmpty ? statusLabel : record.displayText)
                    .font(Theme.Fonts.callout())
                    .foregroundStyle(record.displayText.isEmpty ? Theme.Colors.muted : Theme.Colors.ink)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                statusView
            }
            Text(meta)
                .font(Theme.Fonts.caption())
                .foregroundStyle(Theme.Colors.muted)
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    @ViewBuilder private var statusView: some View {
        if record.status == "failed" {
            Text("Failed")
                .font(Theme.Fonts.caption())
                .foregroundStyle(Theme.Colors.recording)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Theme.Colors.recording.opacity(0.12)))
        } else if record.status == "queuedForRetry" {
            StatusChip(text: "Waiting to send", tone: .pending)
        }
    }

    private var meta: String {
        let time = record.startedAt.formatted(date: .omitted, time: .shortened)
        return [time, AppNames.name(for: record)].compactMap { $0 }.joined(separator: " · ")
    }

    private var statusLabel: String {
        switch record.status {
        case "failed": return "Failed"
        case "queuedForRetry": return "Waiting to send"
        case "silent": return "No speech"
        case "cancelled": return "Cancelled"
        case "recording", "recorded", "transcribing": return "In progress"
        default: return "Empty"
        }
    }
}

private struct HistoryDetail: View {
    @EnvironmentObject private var model: AppModel
    let record: DictationRecord
    let reload: () -> Void
    @State private var message: String?
    @State private var retrying = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                if !record.displayText.isEmpty { transcriptCard }
                if let raw = record.rawTranscript, raw != record.displayText {
                    cardGroup("As heard") {
                        Text(raw)
                            .font(Theme.Fonts.body())
                            .foregroundStyle(Theme.Colors.muted)
                            .textSelection(.enabled)
                    }
                }
                if record.status == "failed" || record.status == "queuedForRetry" { retryCard }
                cardGroup("Details") { details }
            }
            .padding(.horizontal, Theme.Spacing.page)
            .padding(.vertical, Theme.Spacing.l)
        }
        .themedBackground()
        .navigationTitle("Dictation")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var transcriptCard: some View {
        Card {
            Text(record.displayText)
                .font(Theme.Fonts.body())
                .foregroundStyle(Theme.Colors.ink)
                .textSelection(.enabled)
            HStack(spacing: Theme.Spacing.s) {
                Button { UIPasteboard.general.string = record.displayText } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.compactSecondary)
                ShareLink(item: record.displayText) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.compactSecondary)
            }
        }
    }

    private var retryCard: some View {
        Card {
            Button(retrying ? "Retrying…" : "Retry") {
                retrying = true
                Task {
                    message = await model.retry(record)
                    retrying = false
                    reload()
                }
            }
            .buttonStyle(.primaryPill)
            .disabled(retrying)
            if let message {
                Text(message).font(Theme.Fonts.footnote()).foregroundStyle(Theme.Colors.muted)
            }
        }
    }

    private var details: some View {
        VStack(spacing: 0) {
            DetailRow(label: "When", value: record.startedAt.formatted(date: .abbreviated, time: .shortened))
            if let app = AppNames.name(for: record) { divider; DetailRow(label: "App", value: app) }
            if let seconds = record.durationSeconds {
                divider
                DetailRow(label: "Length", value: Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond)))
            }
            if let error = record.errorMessage ?? record.errorCode { divider; DetailRow(label: "Error", value: error) }
        }
    }

    private var divider: some View { Divider().overlay(Theme.Colors.hairline) }

    private func cardGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            GroupLabel(text: title)
            Card { content() }
        }
    }
}

private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.l) {
            Text(label).font(Theme.Fonts.footnote()).foregroundStyle(Theme.Colors.muted)
            Spacer(minLength: Theme.Spacing.l)
            Text(value)
                .font(Theme.Fonts.footnote())
                .foregroundStyle(Theme.Colors.ink)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, Theme.Spacing.s)
    }
}
