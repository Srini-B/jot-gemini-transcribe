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
import GRDB

/// What the user was doing when a model call happened.
public enum UsageActivity: String, Codable, CaseIterable, Sendable {
    case dictation, askAnything, translate, meeting, other

    public var displayName: String {
        switch self {
        case .dictation: return "Dictation"
        case .askAnything: return "Ask Anything"
        case .translate: return "Translate"
        case .meeting: return "Meetings"
        case .other: return "Other"
        }
    }
}

/// Which call inside that activity. One dictation is typically a live
/// transcription plus a cleanup; one meeting is a transcription plus a summary.
public enum UsageStage: String, Codable, Sendable {
    case liveTranscribe, transcribe, cleanup, answer, translate, webQuery, meetingTranscribe, meetingSummary

    public var displayName: String {
        switch self {
        case .liveTranscribe: return "Live transcription"
        case .transcribe: return "Transcription"
        case .cleanup: return "Cleanup"
        case .answer: return "Answer"
        case .translate: return "Translation"
        case .webQuery: return "Web query"
        case .meetingTranscribe: return "Meeting transcription"
        case .meetingSummary: return "Meeting notes"
        }
    }
}

/// One billed model call.
public struct UsageRecord: Codable, Equatable, Identifiable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "usage"

    public var id: String
    public var at: Date
    public var activity: String
    public var stage: String
    public var model: String
    /// Dictation session UUID or meeting ID, so History can show per-item cost.
    public var sessionID: String?
    public var textIn: Int
    public var audioIn: Int
    public var imageIn: Int
    public var cachedIn: Int
    public var textOut: Int
    public var audioOut: Int
    public var thoughtOut: Int
    public var isEstimated: Bool
    /// Paid-tier USD at the time of the call; nil when the model is unpriced.
    public var costUSD: Double?

    public init(at: Date = Date(), activity: UsageActivity, stage: UsageStage, model: String,
                sessionID: String?, usage: TokenUsage) {
        self.id = UUID().uuidString
        self.at = at
        self.activity = activity.rawValue
        self.stage = stage.rawValue
        self.model = model
        self.sessionID = sessionID
        self.textIn = usage.textIn; self.audioIn = usage.audioIn; self.imageIn = usage.imageIn
        self.cachedIn = usage.cachedIn; self.textOut = usage.textOut; self.audioOut = usage.audioOut
        self.thoughtOut = usage.thoughtOut; self.isEstimated = usage.isEstimated
        self.costUSD = PriceBook.cost(model: model, usage: usage, at: at)
    }

    public var usage: TokenUsage {
        TokenUsage(textIn: textIn, audioIn: audioIn, imageIn: imageIn, cachedIn: cachedIn,
                   textOut: textOut, audioOut: audioOut, thoughtOut: thoughtOut, isEstimated: isEstimated)
    }
    public var activityValue: UsageActivity { UsageActivity(rawValue: activity) ?? .other }
    public var stageValue: UsageStage? { UsageStage(rawValue: stage) }
}

public extension Notification.Name {
    static let gtUsageDidChange = Notification.Name("io.blue.voiceiq.usage-changed")
}

/// Append-only ledger of model calls, separate from history.sqlite so
/// deleting a dictation's audio never erases what it cost.
public final class UsageStore: @unchecked Sendable {
    private let queue: DatabaseQueue

    public init(databaseURL: URL) throws {
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            try db.execute(sql: "PRAGMA synchronous = NORMAL")
        }
        queue = try DatabaseQueue(path: databaseURL.path, configuration: config)
        try migrate()
    }

    public static func standard() throws -> UsageStore {
        try UsageStore(databaseURL: FileLayout.appSupportRoot.appendingPathComponent("usage.sqlite"))
    }

    public static func inMemory() throws -> UsageStore {
        try UsageStore(databaseURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("voiceiq-usage-\(UUID().uuidString).sqlite"))
    }

    private func migrate() throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: UsageRecord.databaseTableName) { t in
                t.primaryKey("id", .text)
                t.column("at", .datetime).notNull().indexed()
                t.column("activity", .text).notNull().indexed()
                t.column("stage", .text).notNull()
                t.column("model", .text).notNull().indexed()
                t.column("sessionID", .text).indexed()
                for column in ["textIn", "audioIn", "imageIn", "cachedIn", "textOut", "audioOut", "thoughtOut"] {
                    t.column(column, .integer).notNull().defaults(to: 0)
                }
                t.column("isEstimated", .boolean).notNull().defaults(to: false)
                t.column("costUSD", .double)
            }
        }
        try migrator.migrate(queue)
    }

    // MARK: - Writes

    public func append(_ record: UsageRecord) {
        do {
            try queue.write { db in try record.insert(db) }
            NotificationCenter.default.post(name: .gtUsageDidChange, object: nil)
        } catch {
            Log.usage.error("UsageStore: append failed: \(error)")
        }
    }

    public func deleteAll() {
        do {
            _ = try queue.write { db in try UsageRecord.deleteAll(db) }
            NotificationCenter.default.post(name: .gtUsageDidChange, object: nil)
        } catch {
            Log.usage.error("UsageStore: deleteAll failed: \(error)")
        }
    }

    // MARK: - Reads

    public struct Total: Equatable, Sendable {
        public var costUSD: Double
        public var calls: Int
        public var tokensIn: Int
        public var tokensOut: Int
        /// True when any call in the total had no price entry or estimated tokens.
        public var isApproximate: Bool
        public static let zero = Total(costUSD: 0, calls: 0, tokensIn: 0, tokensOut: 0, isApproximate: false)
    }

    public func total(since start: Date? = nil) -> Total {
        totals(groupedBy: nil, since: start).first?.total ?? .zero
    }

    public func totalsByActivity(since start: Date? = nil) -> [(key: String, total: Total)] {
        totals(groupedBy: "activity", since: start)
    }

    public func totalsByModel(since start: Date? = nil) -> [(key: String, total: Total)] {
        totals(groupedBy: "model", since: start)
    }

    private func totals(groupedBy column: String?, since start: Date?) -> [(key: String, total: Total)] {
        let keyExpression = column ?? "''"
        var sql = """
            SELECT \(keyExpression) AS key,
                   COALESCE(SUM(costUSD), 0) AS cost,
                   COUNT(*) AS calls,
                   COALESCE(SUM(textIn + audioIn + imageIn + cachedIn), 0) AS tokensIn,
                   COALESCE(SUM(textOut + audioOut + thoughtOut), 0) AS tokensOut,
                   MAX(CASE WHEN costUSD IS NULL OR isEstimated THEN 1 ELSE 0 END) AS approx
            FROM usage
            """
        var arguments: StatementArguments = []
        if let start {
            sql += " WHERE at >= ?"
            arguments = [start]
        }
        if let column { sql += " GROUP BY \(column) ORDER BY cost DESC" }
        do {
            return try queue.read { db in
                try Row.fetchAll(db, sql: sql, arguments: arguments).map { row in
                    (row["key"] as String,
                     Total(costUSD: row["cost"], calls: row["calls"], tokensIn: row["tokensIn"],
                           tokensOut: row["tokensOut"], isApproximate: (row["approx"] as Int? ?? 0) == 1))
                }
            }
        } catch {
            Log.usage.error("UsageStore: totals failed: \(error)")
            return []
        }
    }

    /// Cost per session for the History list. Nil entries mean unpriced.
    public func costBySession(ids: [String]) -> [String: Double] {
        guard !ids.isEmpty else { return [:] }
        do {
            return try queue.read { db in
                let rows = try Row.fetchAll(
                    db,
                    sql: "SELECT sessionID, SUM(costUSD) AS cost FROM usage WHERE sessionID IN (\(databaseQuestionMarks(count: ids.count))) GROUP BY sessionID",
                    arguments: StatementArguments(ids)
                )
                var result: [String: Double] = [:]
                for row in rows {
                    if let id = row["sessionID"] as String?, let cost = row["cost"] as Double? { result[id] = cost }
                }
                return result
            }
        } catch {
            Log.usage.error("UsageStore: costBySession failed: \(error)")
            return [:]
        }
    }

    public func records(forSession id: String) -> [UsageRecord] {
        (try? queue.read { db in
            try UsageRecord.filter(Column("sessionID") == id).order(Column("at")).fetchAll(db)
        }) ?? []
    }

    public func recent(limit: Int = 50) -> [UsageRecord] {
        (try? queue.read { db in
            try UsageRecord.order(Column("at").desc).limit(limit).fetchAll(db)
        }) ?? []
    }
}
