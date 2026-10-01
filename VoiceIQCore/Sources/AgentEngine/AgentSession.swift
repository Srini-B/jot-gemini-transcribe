import Foundation

/// A JSON value, for tool arguments that arrive from four differently
/// shaped envelopes and must round-trip into the next request unchanged.
public enum JSONValue: Equatable, Sendable, Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    public init?(any: Any) {
        switch any {
        case let value as String: self = .string(value)
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() { self = .bool(value.boolValue) } else { self = .number(value.doubleValue) }
        case is NSNull: self = .null
        case let value as [Any]: self = .array(value.compactMap(JSONValue.init(any:)))
        case let value as [String: Any]: self = .object(value.compactMapValues(JSONValue.init(any:)))
        default: return nil
        }
    }

    /// Foundation form, for `JSONSerialization` request bodies.
    public var anyValue: Any {
        switch self {
        case .string(let value): return value
        case .number(let value): return value == value.rounded() && abs(value) < 1e15 ? Int(value) : value
        case .bool(let value): return value
        case .null: return NSNull()
        case .array(let value): return value.map(\.anyValue)
        case .object(let value): return value.mapValues(\.anyValue)
        }
    }

    public var stringValue: String? { if case .string(let value) = self { return value }; return nil }
    public var doubleValue: Double? { if case .number(let value) = self { return value }; return nil }
    public var boolValue: Bool? { if case .bool(let value) = self { return value }; return nil }
    public var intValue: Int? { doubleValue.map { Int($0) } }
    public var objectValue: [String: JSONValue]? { if case .object(let value) = self { return value }; return nil }
}

/// What the model asked the executor to do, in one request.
public struct AgentToolCall: Equatable, Sendable, Codable, Identifiable {
    public var id: String
    public var name: String
    public var arguments: [String: JSONValue]

    public init(id: String, name: String, arguments: [String: JSONValue]) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }

    public func string(_ key: String) -> String? { arguments[key]?.stringValue }
    public func int(_ key: String) -> Int? { arguments[key]?.intValue }
    public func bool(_ key: String) -> Bool? { arguments[key]?.boolValue }
}

/// How an executed step ended, for the transcript and the model.
public enum AgentActionStatus: Equatable, Sendable, Codable {
    case running
    case done
    case failed(String)
    case declined
}

/// One line of the transcript. The list is also the model's context, so the
/// display model and the prompt model are one structure.
public enum AgentEntry: Equatable, Sendable, Identifiable, Codable {
    /// What the user said.
    case command(id: UUID, text: String, at: Date)
    /// Model text that is not the final answer.
    case thought(id: UUID, text: String)
    /// A tool call and how it went.
    case action(id: UUID, call: AgentToolCall, summary: String, status: AgentActionStatus)
    /// What the agent saw before deciding.
    case observation(id: UUID, summary: String)
    /// The reply to a question, or the closing line of a task.
    case answer(id: UUID, text: String)
    /// The agent asked before a risky step; `allowed` is nil while waiting.
    case confirmation(id: UUID, request: String, allowed: Bool?)
    /// Something that stopped the turn: a network failure, a refused key.
    case failure(id: UUID, text: String)

    public var id: UUID {
        switch self {
        case .command(let id, _, _), .thought(let id, _), .action(let id, _, _, _),
             .observation(let id, _), .answer(let id, _), .confirmation(let id, _, _), .failure(let id, _):
            return id
        }
    }

    /// The one line the collapsed pill shows.
    public var statusLine: String {
        switch self {
        case .command(_, let text, _): return text
        case .thought(_, let text): return text
        case .action(_, _, let summary, let status):
            switch status {
            case .running: return summary
            case .done: return "Done: \(summary)"
            case .failed(let reason): return "Failed: \(summary) (\(reason))"
            case .declined: return "Skipped: \(summary)"
            }
        case .observation(_, let summary): return summary
        case .answer(_, let text): return text
        case .confirmation(_, let request, _): return request
        case .failure(_, let text): return text
        }
    }
}

/// One agent session: open from the shortcut until Stop. Append-only, so
/// the prompt prefix the hosts cache never changes under them.
public struct AgentSession: Equatable, Sendable, Identifiable, Codable {
    public var id: UUID
    public var startedAt: Date
    public var endpointLabel: String
    public var modelID: String
    public var entries: [AgentEntry]

    public init(id: UUID = UUID(), startedAt: Date = Date(), endpointLabel: String, modelID: String, entries: [AgentEntry] = []) {
        self.id = id
        self.startedAt = startedAt
        self.endpointLabel = endpointLabel
        self.modelID = modelID
        self.entries = entries
    }

    /// The first thing the user said, as the run's title.
    public var title: String {
        for entry in entries { if case .command(_, let text, _) = entry { return text } }
        return "Agent run"
    }

    /// Spoken commands in this run.
    public var commandCount: Int {
        entries.reduce(0) { if case .command = $1 { return $0 + 1 }; return $0 }
    }

    /// Plain text of the whole session, for the clipboard.
    public var transcriptText: String {
        entries.map { entry -> String in
            switch entry {
            case .command(_, let text, _): return "You: \(text)"
            case .thought(_, let text): return "Agent: \(text)"
            case .action(_, _, let summary, let status):
                switch status {
                case .running: return "Action: \(summary)"
                case .done: return "Action: \(summary) — done"
                case .failed(let reason): return "Action: \(summary) — failed: \(reason)"
                case .declined: return "Action: \(summary) — not allowed"
                }
            case .observation(_, let summary): return "Saw: \(summary)"
            case .answer(_, let text): return "Agent: \(text)"
            case .confirmation(_, let request, let allowed):
                return "Asked: \(request) — \(allowed == true ? "allowed" : allowed == false ? "declined" : "pending")"
            case .failure(_, let text): return "Error: \(text)"
            }
        }.joined(separator: "\n")
    }
}
