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

/// URLs the keyboard uses to open the app.
public enum BridgeURL {
    public static let scheme = "voiceiq"

    /// Opened when the app has no live session: the app acts on command `id`
    /// (already in `SharedStore`), then sends the user back to `host`.
    public static func start(commandID: UUID, host: String?) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "keyboard"
        components.path = "/start"
        var items = [URLQueryItem(name: "cmd", value: commandID.uuidString)]
        if let host, !host.isEmpty { items.append(URLQueryItem(name: "host", value: host)) }
        components.queryItems = items
        return components.url!
    }

    /// Opens the app's keyboard setup screen (Full Access missing).
    public static let setup = URL(string: "voiceiq://keyboard/setup")!

    public enum Route: Equatable {
        case start(commandID: UUID, host: String?)
        case setup
    }

    public static func parse(_ url: URL) -> Route? {
        guard url.scheme == scheme, url.host == "keyboard",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let items = components.queryItems ?? []
        switch url.path {
        case "/start":
            guard let raw = items.first(where: { $0.name == "cmd" })?.value,
                  let id = UUID(uuidString: raw) else { return nil }
            return .start(commandID: id, host: items.first(where: { $0.name == "host" })?.value)
        case "/setup":
            return .setup
        default:
            return nil
        }
    }
}
