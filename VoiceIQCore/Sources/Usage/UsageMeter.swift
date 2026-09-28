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

/// Which user action a model call belongs to. Carried as a task-local so the
/// transport can attribute every call without threading a parameter through
/// the transcription service, the coordinator, and the retry queue.
public struct UsageScope: Equatable, Sendable {
    public var activity: UsageActivity
    public var sessionID: String?

    public init(activity: UsageActivity, sessionID: String?) {
        self.activity = activity
        self.sessionID = sessionID
    }

    public init(mode: DictationMode, sessionID: String?) {
        switch mode {
        case .dictate: self.init(activity: .dictation, sessionID: sessionID)
        case .askAnything: self.init(activity: .askAnything, sessionID: sessionID)
        case .translate: self.init(activity: .translate, sessionID: sessionID)
        }
    }
}

/// The single write path into `UsageStore`. `GeminiClient.post` and the live
/// session call `record`; nothing else does.
public enum UsageMeter {
    @TaskLocal public static var scope: UsageScope?

    /// Set once at launch. Nil (tests, onboarding key checks) means calls are
    /// logged but not stored.
    nonisolated(unsafe) public static var store: UsageStore?

    public static func record(stage: UsageStage, model: String, usage: TokenUsage) {
        // Per-minute models report a charge and no tokens.
        guard !usage.isEmpty || usage.reportedCostUSD != nil else { return }
        let scope = self.scope ?? UsageScope(activity: .other, sessionID: nil)
        let record = UsageRecord(activity: scope.activity, stage: stage, model: model,
                                 sessionID: scope.sessionID, usage: usage)
        let cost = record.costUSD.map { String(format: "$%.5f", $0) } ?? "unpriced"
        Log.usage.info(
            "usage \(scope.activity.rawValue, privacy: .public)/\(stage.rawValue, privacy: .public) \(model, privacy: .public): in \(usage.totalIn, privacy: .public) (audio \(usage.audioIn, privacy: .public), image \(usage.imageIn, privacy: .public)) out \(usage.totalOut, privacy: .public)\(usage.isEstimated ? " est" : "", privacy: .public) \(cost, privacy: .public)"
        )
        store?.append(record)
    }
}
