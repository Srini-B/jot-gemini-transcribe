// Copyright 2026 Google LLC
// Licensed under the Apache License, Version 2.0.

import Foundation

/// TinyFish Search + Fetch (docs.tinyfish.ai). Gives Ask Anything fresh web
/// context when the user has entered a TinyFish key. Both APIs are free; the
/// account only needs Search access (402 otherwise).
///
///   GET  https://api.search.tinyfish.ai?query=…      header X-API-Key
///   POST https://api.fetch.tinyfish.ai  {"urls":[…],"format":"markdown"}
public final class TinyFishClient: Sendable {
    public struct SearchResult: Sendable, Equatable {
        public let title: String
        public let url: String
        public let snippet: String
    }

    public struct Page: Sendable, Equatable {
        public let url: String
        public let title: String
        public let text: String
    }

    public enum Failure: Error, Equatable {
        case missingKey
        case unauthorized
        case noSearchAccess
        case rateLimited
        case http(Int)
        case unparseable
    }

    public static let searchEndpoint = URL(string: "https://api.search.tinyfish.ai")!
    public static let fetchEndpoint = URL(string: "https://api.fetch.tinyfish.ai")!

    private let apiKey: @Sendable () -> String?
    private let session: URLSession

    public init(apiKey: @escaping @Sendable () -> String?) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 40
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)
        self.apiKey = apiKey
    }

    deinit { session.invalidateAndCancel() }

    // MARK: - Search

    public func search(_ query: String, recencyMinutes: Int? = nil) async throws -> [SearchResult] {
        guard let key = apiKey(), !key.isEmpty else { throw Failure.missingKey }
        var components = URLComponents(url: Self.searchEndpoint, resolvingAgainstBaseURL: false)!
        var items = [URLQueryItem(name: "query", value: query)]
        if let recencyMinutes { items.append(URLQueryItem(name: "recency_minutes", value: String(recencyMinutes))) }
        components.queryItems = items
        var request = URLRequest(url: components.url!)
        request.setValue(key, forHTTPHeaderField: "X-API-Key")
        let data = try await perform(request)
        return try Self.parseSearch(data)
    }

    static func parseSearch(_ data: Data) throws -> [SearchResult] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else {
            throw Failure.unparseable
        }
        return results.compactMap { item in
            guard let url = item["url"] as? String, !url.isEmpty else { return nil }
            return SearchResult(
                title: item["title"] as? String ?? "",
                url: url,
                snippet: item["snippet"] as? String ?? ""
            )
        }
    }

    // MARK: - Fetch

    public func fetch(_ urls: [String], timeoutMs: Int = 20_000) async throws -> [Page] {
        guard let key = apiKey(), !key.isEmpty else { throw Failure.missingKey }
        guard !urls.isEmpty else { return [] }
        var request = URLRequest(url: Self.fetchEndpoint)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "X-API-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "urls": Array(urls.prefix(10)),
            "format": "markdown",
            "per_url_timeout_ms": min(110_000, max(1, timeoutMs)),
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data = try await perform(request)
        return try Self.parseFetch(data)
    }

    static func parseFetch(_ data: Data) throws -> [Page] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else {
            throw Failure.unparseable
        }
        return results.compactMap { item in
            guard let text = item["text"] as? String, !text.isEmpty else { return nil }
            // `url` echoes the request; `final_url` may differ after redirects
            // (or just drop a trailing slash), so callers match on `url`.
            return Page(
                url: item["url"] as? String ?? item["final_url"] as? String ?? "",
                title: item["title"] as? String ?? "",
                text: text
            )
        }
    }

    // MARK: - Key check

    public enum KeyCheck: Equatable { case valid, rejected, unreachable }

    /// One cheap search. 401 means a bad key; 402 means the account lacks
    /// Search access, which is also a rejection from the user's point of view.
    public func validateKey() async -> KeyCheck {
        do {
            _ = try await search("voice iq")
            return .valid
        } catch Failure.unauthorized, Failure.noSearchAccess {
            return .rejected
        } catch {
            return .unreachable
        }
    }

    // MARK: - Transport

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw Failure.unparseable }
        switch http.statusCode {
        case 200..<300: return data
        case 401: throw Failure.unauthorized
        case 402: throw Failure.noSearchAccess
        case 429: throw Failure.rateLimited
        default:
            Log.transcription.error("tinyfish http \(http.statusCode, privacy: .public)")
            throw Failure.http(http.statusCode)
        }
    }
}
