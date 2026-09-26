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
import JotCore

/// `InsertionCoordinator` plus auto-learn: harvest the user's edits to earlier
/// insertions in this field before the new text lands, then track the new text.
///
/// Wrapping the inserter rather than teaching `DictationCoordinator` about
/// learning keeps the session state machine unaware of the dictionary; the only
/// thing this adds is an AX read on either side of the insert.
@MainActor
final class LearningInserter: TextInserting {
    private let inner = InsertionCoordinator()
    let learner: EditLearner

    init(learner: EditLearner) {
        self.learner = learner
    }

    func insert(_ text: String, context: DictationContext) async -> InsertionOutcome {
        let enabled = SettingsStore().autoLearnEnabled
        let field = enabled
            ? AXInserter.focusedField(targetPID: context.targetPID, bundleID: context.targetAppBundleID)
            : nil
        if let field { learner.harvest(before: field) }
        let outcome = await inner.insert(text, context: context)
        if outcome == .inserted, let field { learner.track(inserted: text, in: field) }
        return outcome
    }
}
