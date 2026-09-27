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

    var body: some View {
        NavigationStack {
            List {
                ForEach(records) { record in
                    NavigationLink { HistoryDetail(record: record, reload: reload) } label: {
                        HistoryRow(record: record)
                    }
                }
                .onDelete { offsets in
                    for index in offsets { model.historyStore?.delete(id: records[index].id, removeFolder: true) }
                    reload()
                }
            }
            .overlay {
                if records.isEmpty {
                    ContentUnavailableView(search.isEmpty ? "No dictations yet" : "No results", systemImage: "clock")
                }
            }
            .searchable(text: $search)
            .onChange(of: search) { _, _ in reload() }
            .navigationTitle("History")
            .toolbar {
                if !records.isEmpty {
                    Button("Delete All", role: .destructive) { confirmDeleteAll = true }
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

    private func reload() {
        records = model.historyStore?.records(matching: search.isEmpty ? nil : search) ?? []
    }
}

private struct HistoryRow: View {
    let record: DictationRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(record.displayText.isEmpty ? statusLabel : record.displayText)
                .lineLimit(3)
                .foregroundStyle(record.displayText.isEmpty ? .secondary : .primary)
            HStack(spacing: 6) {
                Text(record.startedAt, format: .relative(presentation: .named))
                if let app = record.targetAppName { Text("· \(app)") }
                if needsAttention { Text("· \(statusLabel)").foregroundStyle(Brand.recording) }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var needsAttention: Bool {
        record.status == "failed" || record.status == "queuedForRetry"
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
        Form {
            if !record.displayText.isEmpty {
                Section {
                    Text(record.displayText).textSelection(.enabled)
                    Button("Copy") { UIPasteboard.general.string = record.displayText }
                }
            }
            if let raw = record.rawTranscript, raw != record.displayText {
                Section("As heard") {
                    Text(raw).textSelection(.enabled).foregroundStyle(.secondary)
                }
            }
            if record.status == "failed" || record.status == "queuedForRetry" {
                Section {
                    Button(retrying ? "Retrying…" : "Retry") {
                        retrying = true
                        Task {
                            message = await model.retry(record)
                            retrying = false
                            reload()
                        }
                    }
                    .disabled(retrying)
                    if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
                }
            }
            Section {
                LabeledContent("When", value: record.startedAt.formatted(date: .abbreviated, time: .shortened))
                if let app = record.targetAppName { LabeledContent("App", value: app) }
                if let seconds = record.durationSeconds {
                    LabeledContent("Length", value: Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond)))
                }
                if let error = record.errorMessage ?? record.errorCode { LabeledContent("Error", value: error) }
            }
        }
        .navigationTitle("Dictation")
        .navigationBarTitleDisplayMode(.inline)
    }
}
