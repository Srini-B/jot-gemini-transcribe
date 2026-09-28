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

/// Cross-process pings between the app and its extensions.
///
/// Darwin notifications carry no payload and are dropped while the receiver is
/// suspended, so a ping only ever means "reread `SharedStore`". Readers must
/// also reread on their own lifecycle events (keyboard appearing, app becoming
/// active) instead of trusting that every ping arrived.
public enum DarwinNotifier {
    public enum Name: String, CaseIterable, Sendable {
        /// Keyboard → app: a command was appended.
        case command = "io.blue.voiceiq.bridge.command"
        /// App → keyboard: the snapshot changed.
        case state = "io.blue.voiceiq.bridge.state"
        /// The keyboard ran with Full Access. Writer: keyboard.
        case keyboard = "io.blue.voiceiq.bridge.keyboard"
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handlers: [Name: [UUID: @Sendable () -> Void]] = [:]
    nonisolated(unsafe) private static var registered: Set<Name> = []

    public static func post(_ name: Name) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(name.rawValue as CFString),
            nil, nil, true
        )
    }

    /// Calls `handler` on the main queue for every ping. Keep the token and
    /// pass it to `removeObserver` when done.
    @discardableResult
    public static func observe(_ name: Name, handler: @escaping @Sendable () -> Void) -> UUID {
        let token = UUID()
        lock.lock()
        handlers[name, default: [:]][token] = handler
        let needsRegistration = registered.insert(name).inserted
        lock.unlock()
        if needsRegistration {
            CFNotificationCenterAddObserver(
                CFNotificationCenterGetDarwinNotifyCenter(),
                nil,
                { _, _, cfName, _, _ in
                    guard let raw = cfName?.rawValue as String?, let name = Name(rawValue: raw) else { return }
                    DarwinNotifier.dispatch(name)
                },
                name.rawValue as CFString,
                nil,
                .deliverImmediately
            )
        }
        return token
    }

    public static func removeObserver(_ token: UUID) {
        lock.lock()
        for name in handlers.keys { handlers[name]?[token] = nil }
        lock.unlock()
    }

    private static func dispatch(_ name: Name) {
        lock.lock()
        let targets = Array((handlers[name] ?? [:]).values)
        lock.unlock()
        DispatchQueue.main.async { targets.forEach { $0() } }
    }
}
