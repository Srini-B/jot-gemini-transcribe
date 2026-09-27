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

public final class MeetingStore: @unchecked Sendable {
    public let root: URL
    private let encoder: JSONEncoder = { let value = JSONEncoder(); value.outputFormatting = [.prettyPrinted, .sortedKeys]; return value }()
    private let decoder = JSONDecoder()

    public init(root: URL = FileLayout.meetingsRoot) { self.root = root }
    public func folder(for id: MeetingID) -> URL? {
        try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .first { $0.lastPathComponent.hasSuffix(id.uuid.uuidString) }
    }
    public func create(meta: MeetingMeta) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let date = meta.startedAt.formatted(.iso8601.year().month().day().dateSeparator(.dash))
        let folder = root.appendingPathComponent("\(date)-\(meta.id.uuid.uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try save(meta, in: folder, name: "meta.json")
        return folder
    }
    public func list() -> [MeetingMeta] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return urls.compactMap { try? load(MeetingMeta.self, from: $0.appendingPathComponent("meta.json")) }
            .sorted { $0.startedAt > $1.startedAt }
    }
    public func loadTranscript(id: MeetingID) throws -> [TranscriptSegment] { try load([TranscriptSegment].self, from: requiredFolder(id).appendingPathComponent("transcript.json")) }
    public func loadNotes(id: MeetingID) throws -> MeetingNotes { try load(MeetingNotes.self, from: requiredFolder(id).appendingPathComponent("notes.json")) }
    public func save(meta: MeetingMeta) throws { try save(meta, in: requiredFolder(meta.id), name: "meta.json") }
    public func save(transcript: [TranscriptSegment], id: MeetingID) throws { try save(transcript, in: requiredFolder(id), name: "transcript.json") }
    public func save(notes: MeetingNotes, id: MeetingID) throws { try save(notes, in: requiredFolder(id), name: "notes.json") }
    public func delete(id: MeetingID) throws { try FileManager.default.removeItem(at: requiredFolder(id)) }
    public func renameSpeaker(id: MeetingID, label: String, name: String) throws {
        var meta = try load(MeetingMeta.self, from: requiredFolder(id).appendingPathComponent("meta.json"))
        meta.speakerNames[label] = name.trimmingCharacters(in: .whitespacesAndNewlines)
        try save(meta: meta)
    }
    public func exportMarkdown(id: MeetingID) throws -> String {
        let folder = try requiredFolder(id), meta = try load(MeetingMeta.self, from: folder.appendingPathComponent("meta.json"))
        let notes = try loadNotes(id: id), transcript = try loadTranscript(id: id)
        var lines = ["# \(notes.title)", "", meta.startedAt.formatted(date: .long, time: .shortened),
                     String(format: "%.0f minutes", meta.durationSeconds / 60), "", "## Summary", notes.summary]
        for section in notes.sections ?? [] { append(section.title, section.items, to: &lines) }
        append("Decisions", notes.decisions, to: &lines)
        if !notes.actions.isEmpty { lines += ["", "## Action items"] + notes.actions.map { item in
            var suffix = [item.owner, item.deadline].compactMap { $0 }.joined(separator: " · ")
            if !suffix.isEmpty { suffix = " (\(suffix))" }; return "- \(item.text)\(suffix)"
        }}
        append("Notes", notes.notes, to: &lines)
        lines += ["", "## Transcript"] + transcript.map { segment in
            let time = segment.start.map { "[\(MeetingNotesPrompt.clock($0))] " } ?? ""
            return "\(time)**\(MeetingSpeaker.displayName(segment.speaker, names: meta.speakerNames, suggested: notes.speakers)):** \(segment.text)"
        }
        let markdown = lines.joined(separator: "\n") + "\n"
        try markdown.write(to: folder.appendingPathComponent("notes.md"), atomically: true, encoding: .utf8)
        return markdown
    }
    private func requiredFolder(_ id: MeetingID) throws -> URL {
        guard let folder = folder(for: id) else { throw CocoaError(.fileNoSuchFile) }; return folder
    }
    private func load<T: Decodable>(_ type: T.Type, from url: URL) throws -> T { try decoder.decode(type, from: Data(contentsOf: url)) }
    private func save<T: Encodable>(_ value: T, in folder: URL, name: String) throws { try encoder.encode(value).write(to: folder.appendingPathComponent(name), options: .atomic) }
    private func append(_ title: String, _ items: [String], to lines: inout [String]) { if !items.isEmpty { lines += ["", "## \(title)"] + items.map { "- \($0)" } } }
}
