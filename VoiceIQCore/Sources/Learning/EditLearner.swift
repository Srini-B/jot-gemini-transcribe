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

#if os(macOS)
import Foundation

/// Learns dictionary corrections from the user's edits to earlier insertions.
///
/// The accessibility read and the diff run off the main actor: a long
/// document with several tracked insertions took whole seconds of CPU, and
/// doing that on the main thread every poll froze the hotkey, the pill and
/// the tray menu. Only bookkeeping and dictionary writes touch the main actor.
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
        /// Hash of the field value the last diff ran against.
        var lastValueHash: Int?
        /// A value seen since then that has not yet held still long enough
        /// to be diffed, and when it was first seen.
        var pendingHash: Int?
        var pendingSince: Date?
        var pollTask: Task<Void, Never>?
        var harvesting = false
    }

    /// One matched insertion after a harvest: its text now reads `window`.
    private struct Located: Sendable {
        let id: UUID
        let window: String
        let corrections: [LearnedCorrection]
    }

    private enum Harvest: Sendable {
        case fieldGone
        case unchanged
        /// The field changed but is still being edited: `valueHash` is the
        /// value seen now, to be diffed once it has held still.
        case editing(valueHash: Int)
        case located([Located], valueHash: Int)
    }

    /// Fields above this size are not diffed; the harvest would cost more than
    /// the corrections are worth and the user is unlikely to be dictating there.
    nonisolated static let maximumFieldLength = 200_000

    /// A changed field is diffed only after its value has stayed the same for
    /// this long. Diffing mid-edit learned half-typed words ("Pastack" while
    /// the user was on the way from "Paystack" to "pstack").
    nonisolated static let settleSeconds: TimeInterval = 4

    private let dictionary: DictionaryStore
    private var fields: [FieldKey: TrackedField] = [:]
    public var onLearned: (([DictionaryEntry]) -> Void)?

    public init(dictionary: DictionaryStore = DictionaryStore()) {
        self.dictionary = dictionary
    }

    private static let pruneFlag = "didPruneOrdinaryAutoLearned"

    /// One-time: removes auto-learned entries that are ordinary words, learned
    /// before the rule above existed. Entries the user added are untouched.
    /// The removal syncs to the iPhone like any other deletion.
    public static func pruneOrdinaryAutoLearnedOnce(dictionary: DictionaryStore = DictionaryStore()) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: pruneFlag) else { return }
        defaults.set(true, forKey: pruneFlag)
        let entries = dictionary.entries()
        let kept = entries.filter { $0.source != .auto || !CommonWords.isOrdinary($0.term) }
        guard kept.count != entries.count else { return }
        dictionary.save(kept)
        Log.learning.info("Removed \(entries.count - kept.count) auto-learned ordinary word(s)")
    }

    deinit {
        for field in fields.values { field.pollTask?.cancel() }
    }

    /// Harvests edits made to earlier insertions in `field`, returning once
    /// they are applied. Callers about to insert new text await this so the
    /// diff sees the field before the new text lands.
    public func harvest(before field: FieldSnapshot) async {
        await harvest(key: FieldKey(field))
    }

    public func track(inserted text: String, in field: FieldSnapshot) {
        let key = FieldKey(field)
        let now = Date()
        var tracked = fields[key] ?? TrackedField(
            snapshot: field,
            insertions: [],
            lastInsertionAt: now
        )
        tracked.insertions.removeAll { now.timeIntervalSince($0.insertedAt) > 7_200 }
        tracked.insertions.append(Insertion(id: UUID(), text: text, insertedAt: now))
        if tracked.insertions.count > 20 {
            tracked.insertions.removeFirst(tracked.insertions.count - 20)
        }
        tracked.lastInsertionAt = now
        tracked.lastValueHash = nil
        tracked.pendingHash = nil
        tracked.pendingSince = nil
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
                await self.harvest(key: key)
                guard self.fields[key] != nil else { return }
            }
        }
    }

    private func harvest(key: FieldKey) async {
        guard var tracked = fields[key], !tracked.harvesting else { return }
        let now = Date()
        tracked.insertions.removeAll { now.timeIntervalSince($0.insertedAt) > 7_200 }
        guard !tracked.insertions.isEmpty else {
            forget(key)
            return
        }
        tracked.harvesting = true
        fields[key] = tracked

        let snapshot = tracked.snapshot
        let insertions = tracked.insertions.map { ($0.id, $0.text) }
        let previousHash = tracked.lastValueHash
        let settled = tracked.pendingSince.map { now.timeIntervalSince($0) >= Self.settleSeconds } == true
        let settledHash = settled ? tracked.pendingHash : nil
        let result = await Task.detached(priority: .utility) {
            Self.compute(
                snapshot: snapshot,
                insertions: insertions,
                previousHash: previousHash,
                settledHash: settledHash
            )
        }.value

        guard var current = fields[key] else { return }
        current.harvesting = false
        switch result {
        case .fieldGone:
            forget(key)
        case .unchanged:
            fields[key] = current
        case let .editing(valueHash):
            if valueHash != current.pendingHash {
                current.pendingHash = valueHash
                current.pendingSince = now
            }
            fields[key] = current
        case let .located(located, valueHash):
            current.lastValueHash = valueHash
            current.pendingHash = nil
            current.pendingSince = nil
            let harvested = Set(insertions.map(\.0))
            let byID = Dictionary(uniqueKeysWithValues: located.map { ($0.id, $0) })
            current.insertions = current.insertions.compactMap { insertion in
                guard harvested.contains(insertion.id) else { return insertion }
                guard let match = byID[insertion.id] else { return nil }
                var updated = insertion
                updated.text = match.window
                return updated
            }
            guard !current.insertions.isEmpty else {
                forget(key)
                return
            }
            fields[key] = current
            learn(located.flatMap(\.corrections))
        }
    }

    private func forget(_ key: FieldKey) {
        fields[key]?.pollTask?.cancel()
        fields.removeValue(forKey: key)
    }

    private nonisolated static func compute(
        snapshot: FieldSnapshot,
        insertions: [(UUID, String)],
        previousHash: Int?,
        settledHash: Int?
    ) -> Harvest {
        guard let current = snapshot.currentValue(), current.count <= maximumFieldLength else { return .fieldGone }
        let valueHash = current.hashValue
        if valueHash == previousHash { return .unchanged }
        guard valueHash == settledHash else { return .editing(valueHash: valueHash) }
        let matches = EditDiff.locateWindows(insertions: insertions.map(\.1), in: current)
        let located = zip(insertions, matches).compactMap { insertion, match -> Located? in
            guard let match else { return nil }
            return Located(
                id: insertion.0,
                window: match.window,
                corrections: EditDiff.corrections(original: insertion.1, replacement: match.window)
            )
        }
        return .located(located, valueHash: valueHash)
    }

    private func learn(_ corrections: [LearnedCorrection]) {
        var learned: [DictionaryEntry] = []
        var known = dictionary.entries()
        for correction in corrections {
            let original = correction.original.lowercased()
            let replacement = correction.replacement.lowercased()
            guard !known.contains(where: {
                let term = $0.term.lowercased()
                let misspelling = $0.misspelling?.lowercased()
                let learnedFrom = $0.learnedFrom?.lowercased()
                return term == original || term == replacement
                    || misspelling == original || misspelling == replacement
                    || learnedFrom == original
            }) else { continue }
            // Only words the language does not already have: a name, a
            // product term, jargon. Changing "They" to "we" or fixing the
            // case of "There's" is an edit, not a new word.
            guard !CommonWords.isOrdinary(correction.replacement) else {
                Log.learning.info("Skipped an edit to ordinary words")
                continue
            }
            // Learned as a word only, never as a wrong→right rule: a rule
            // built from one edit ("stack" → "pstack") would rewrite every
            // later "stack". The word rides in the vocabulary; `learnedFrom`
            // records the transcript wording it replaced.
            guard dictionary.add(
                term: correction.replacement,
                learnedFrom: correction.original,
                source: .auto
            ) else { continue }
            if let entry = dictionary.entries().last(where: {
                $0.source == .auto && $0.term.caseInsensitiveCompare(correction.replacement) == .orderedSame
            }) {
                learned.append(entry)
                known.append(entry)
            }
        }
        if !learned.isEmpty {
            Log.learning.info("Learned \(learned.count) dictionary correction(s)")
            onLearned?(learned)
        }
    }
}
#endif
