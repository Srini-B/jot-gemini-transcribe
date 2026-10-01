import Foundation

/// Agent runs on disk: one JSON file per session under `agent-runs/`,
/// rewritten whole after every transcript change. Runs are small (text,
/// no screenshots), so the rewrite is cheaper than a journal.
public final class AgentRunStore: @unchecked Sendable {
    public let root: URL
    private let encoder: JSONEncoder = {
        let value = JSONEncoder()
        value.outputFormatting = [.prettyPrinted, .sortedKeys]
        value.dateEncodingStrategy = .iso8601
        return value
    }()
    private let decoder: JSONDecoder = {
        let value = JSONDecoder()
        value.dateDecodingStrategy = .iso8601
        return value
    }()

    public init(root: URL = FileLayout.agentRunsRoot) { self.root = root }

    /// Writes the run, replacing an earlier copy of the same session.
    public func save(_ session: AgentSession) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try encoder.encode(session).write(to: file(for: session.id), options: .atomic)
    }

    /// Every saved run, newest first.
    public func list() -> [AgentSession] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(AgentSession.self, from: Data(contentsOf: $0)) }
            .sorted { $0.startedAt > $1.startedAt }
    }

    public func delete(id: UUID) throws {
        try FileManager.default.removeItem(at: file(for: id))
    }

    public func deleteAll() throws {
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        try FileManager.default.removeItem(at: root)
    }

    private func file(for id: UUID) -> URL {
        root.appendingPathComponent("\(id.uuidString).json")
    }
}
