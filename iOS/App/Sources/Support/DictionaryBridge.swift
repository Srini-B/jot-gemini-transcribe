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
import VoiceIQBridge
import VoiceIQCore

/// The dictionary's links outside the app: iCloud sync with the Mac, words
/// the keyboard queues from a selection or the clipboard, and the word list
/// the keyboard reads to tell whether a selection is already saved.
@MainActor
enum DictionaryBridge {
    /// IDs of keyboard additions already added. Writer: app (own defaults).
    private static let handledKey = "handledDictionaryAdditions"
    private static var observer: UUID?

    static func start() {
        DictionarySync.shared.start()
        NotificationCenter.default.addObserver(forName: .gtDictionaryDidChange, object: nil, queue: .main) { _ in
            Task { @MainActor in publishTerms() }
        }
        observer = DarwinNotifier.observe(.dictionary) {
            Task { @MainActor in addQueuedWords() }
        }
        addQueuedWords()
        publishTerms()
    }

    /// Darwin pings and iCloud changes are not delivered while suspended.
    static func appBecameActive() {
        addQueuedWords()
        DictionarySync.shared.refresh()
    }

    private static func addQueuedWords() {
        let shared = SharedStore.shared
        shared.reloadFromDisk()
        let queued = shared.dictionaryAdditions
        var handled = Set(UserDefaults.standard.stringArray(forKey: handledKey) ?? [])
        for addition in queued where !handled.contains(addition.id.uuidString) {
            let added = DictionaryStore().add(term: addition.term)
            SessionDiagnostics.note("keyboard dictionary word \(added ? "added" : "already saved")")
            handled.insert(addition.id.uuidString)
        }
        // Only IDs still in the keyboard's list can come up again.
        let live = Set(queued.map(\.id.uuidString))
        UserDefaults.standard.set(Array(handled.intersection(live)), forKey: handledKey)
    }

    private static func publishTerms() {
        SharedStore.shared.setDictionaryTerms(DictionaryStore().entries().map(\.term))
    }
}
