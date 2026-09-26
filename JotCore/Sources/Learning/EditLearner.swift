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

@MainActor
public final class EditLearner {
    private struct Insertion {
        let id: UUID
        var text: String
        let insertedAt: Date
    }

    private struct TrackedField {
        let snapshot: FieldSnapshot
        var insertions: [Insertion]
        var lastInsertionAt: Date
        var pollTask: Task<Void, Never>?
    }

    private let dictionary: DictionaryStore
    private var fields: [FieldKey: TrackedField] = [:]
    public var onLearned: (([DictionaryEntry]) -> Void)?

    public init(dictionary: DictionaryStore = DictionaryStore()) {
        self.dictionary = dictionary
    }

    deinit {
        for field in fields.values { field.pollTask?.cancel() }
    }

    public func harvest(before field: FieldSnapshot) {
        harvest(key: FieldKey(field))
    }

    public func track(inserted text: String, in field: FieldSnapshot) {
        let key = FieldKey(field)
        let now = Date()
        var tracked = fields[key] ?? TrackedField(
            snapshot: field,
            insertions: [],
            lastInsertionAt: now,
            pollTask: nil
        )
        tracked.insertions.removeAll { now.timeIntervalSince($0.insertedAt) > 7_200 }
        tracked.insertions.append(Insertion(id: UUID(), text: text, insertedAt: now))
        if tracked.insertions.count > 20 {
            tracked.insertions.removeFirst(tracked.insertions.count - 20)
        }
        tracked.lastInsertionAt = now
        tracked.pollTask?.cancel()
        tracked.pollTask = pollingTask(for: key)
        fields[key] = tracked
        Log.learning.debug("Tracking edit candidates for pid \(field.pid)")
    }

    public func undo(_ entries: [DictionaryEntry]) {
        for entry in entries { dictionary.remove(id: entry.id) }
    }

    private func pollingTask(for key: FieldKey) -> Task<Void, Never> {
        Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let field = self.fields[key] else { return }
                let elapsed = Date().timeIntervalSince(field.lastInsertionAt)
                guard elapsed < 600 else { return }
                let interval: TimeInterval = elapsed < 20 ? 1 : 5
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self.harvest(key: key)
                guard self.fields[key] != nil else { return }
            }
        }
    }

    private func harvest(key: FieldKey) {
        guard var tracked = fields[key] else { return }
        let now = Date()
        tracked.insertions.removeAll { now.timeIntervalSince($0.insertedAt) > 7_200 }
        guard !tracked.insertions.isEmpty, let current = tracked.snapshot.currentValue() else {
            tracked.pollTask?.cancel()
            fields.removeValue(forKey: key)
            return
        }

        let matches = EditDiff.locateWindows(insertions: tracked.insertions.map(\.text), in: current)
        var retained: [Insertion] = []
        var learned: [DictionaryEntry] = []
        var known = dictionary.entries()

        for (insertion, match) in zip(tracked.insertions, matches) {
            guard let match else { continue }
            var updated = insertion
            for correction in EditDiff.corrections(original: insertion.text, replacement: match.window) {
                let original = correction.original.lowercased()
                let replacement = correction.replacement.lowercased()
                guard !known.contains(where: {
                    let term = $0.term.lowercased()
                    let misspelling = $0.misspelling?.lowercased()
                    return term == original || term == replacement
                        || misspelling == original || misspelling == replacement
                }) else { continue }
                guard dictionary.add(
                    term: correction.replacement,
                    misspelling: correction.original,
                    source: .auto
                ) else { continue }
                if let entry = dictionary.entries().last(where: {
                    $0.source == .auto && $0.term.caseInsensitiveCompare(correction.replacement) == .orderedSame
                }) {
                    learned.append(entry)
                    known.append(entry)
                }
            }
            updated.text = match.window
            retained.append(updated)
        }

        guard !retained.isEmpty else {
            tracked.pollTask?.cancel()
            fields.removeValue(forKey: key)
            return
        }
        tracked.insertions = retained
        fields[key] = tracked
        if !learned.isEmpty {
            Log.learning.info("Learned \(learned.count) dictionary correction(s)")
            onLearned?(learned)
        }
    }
}
