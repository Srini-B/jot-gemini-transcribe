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

/// App Group storage shared by the app, the keyboard and the Live Activity.
///
/// Every key has exactly one writer process, named on the property. Two
/// processes never write the same key, so there is nothing to lock: the reader
/// may see a value a moment late, never a torn or overwritten one.
public final class SharedStore: @unchecked Sendable {
    public static let appGroupID = "group.io.blue.voiceiq"
    public static let shared = SharedStore()

    /// The app sends a heartbeat at least this often while a session is up.
    public static let heartbeatInterval: TimeInterval = 1
    /// A heartbeat older than this means the app is gone or suspended.
    public static let heartbeatTimeout: TimeInterval = 3
    /// Commands kept for the app to read. The keyboard trims to this.
    static let commandLimit = 8

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(defaults: UserDefaults? = UserDefaults(suiteName: SharedStore.appGroupID)) {
        self.defaults = defaults ?? .standard
    }

    /// False inside a keyboard that has not been granted Full Access: iOS then
    /// hides the App Group container, and nothing written here reaches the app.
    public static var isContainerReachable: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) != nil
    }

    private enum Key {
        static let commands = "bridge.commands"
        static let handledCommandID = "bridge.handledCommandID"
        static let snapshot = "bridge.snapshot"
        static let heartbeat = "bridge.heartbeat"
        static let level = "bridge.level"
        static let insertedDeliveryID = "bridge.insertedDeliveryID"
        static let keyboardSeenAt = "bridge.keyboardSeenAt"
        static let activityRequest = "bridge.activityRequest"
        static let keyboardLog = "bridge.keyboardLog"
    }

    // MARK: - Keyboard diagnostics

    /// The keyboard's recent decisions (results typed or not, and why), for
    /// the Session log in the app. No text or keys. Writer: keyboard.
    public var keyboardLog: [String] {
        defaults.stringArray(forKey: Key.keyboardLog) ?? []
    }

    public func appendKeyboardLog(_ line: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        var lines = keyboardLog
        lines.append("\(formatter.string(from: Date())) \(line)")
        defaults.set(Array(lines.suffix(100)), forKey: Key.keyboardLog)
    }

    public func clearKeyboardLog() {
        defaults.removeObject(forKey: Key.keyboardLog)
    }

    // MARK: - Keyboard writes

    /// Pending commands, oldest first. Writer: keyboard.
    public var commands: [KeyboardCommand] {
        decode([KeyboardCommand].self, forKey: Key.commands) ?? []
    }

    public func append(_ command: KeyboardCommand) {
        var list = commands.filter { $0.isFresh() }
        list.append(command)
        encode(Array(list.suffix(Self.commandLimit)), forKey: Key.commands)
        DarwinNotifier.post(.command)
    }

    /// The last delivery handled, so a result is inserted once even when
    /// state pings repeat. Writers: the keyboard when it types a result, the
    /// app when no keyboard did and it put the result on the clipboard.
    public var insertedDeliveryID: UUID? {
        get { defaults.string(forKey: Key.insertedDeliveryID).flatMap(UUID.init(uuidString:)) }
        set { defaults.set(newValue?.uuidString, forKey: Key.insertedDeliveryID) }
    }

    /// When a keyboard with Full Access last ran. The app reads it to tell
    /// whether setup is finished. Writer: keyboard.
    public var keyboardSeenAt: Date? {
        get { date(forKey: Key.keyboardSeenAt) }
        set { defaults.set(newValue?.timeIntervalSince1970, forKey: Key.keyboardSeenAt) }
    }

    /// Called by the keyboard each time it appears with Full Access. Pings the
    /// app so a setup screen on show updates at once.
    public func noteKeyboardSeen() {
        keyboardSeenAt = Date()
        DarwinNotifier.post(.keyboard)
    }

    /// Rereads values another process wrote. UserDefaults caches per process;
    /// this drops the cache so a value the keyboard just wrote is visible.
    public func reloadFromDisk() {
        defaults.synchronize()
    }

    // MARK: - Live Activity writes

    /// The last Dynamic Island button press. Writer: the Live Activity intents.
    public var activityRequest: ActivityRequest? {
        decode(ActivityRequest.self, forKey: Key.activityRequest)
    }

    public func request(_ action: ActivityRequest.Action) {
        encode(ActivityRequest(action: action), forKey: Key.activityRequest)
        DarwinNotifier.post(.command)
    }

    // MARK: - App writes

    /// The newest command the app has acted on. Writer: app.
    public var handledCommandID: UUID? {
        get { defaults.string(forKey: Key.handledCommandID).flatMap(UUID.init(uuidString:)) }
        set { defaults.set(newValue?.uuidString, forKey: Key.handledCommandID) }
    }

    /// Writer: app.
    public var snapshot: SessionSnapshot {
        decode(SessionSnapshot.self, forKey: Key.snapshot) ?? SessionSnapshot()
    }

    public func publish(_ snapshot: SessionSnapshot) {
        encode(snapshot, forKey: Key.snapshot)
        DarwinNotifier.post(.state)
    }

    /// Writer: app.
    public var heartbeat: Date? {
        get { date(forKey: Key.heartbeat) }
        set { defaults.set(newValue?.timeIntervalSince1970, forKey: Key.heartbeat) }
    }

    /// Microphone level 0…1 while recording. Writer: app.
    public var level: Float {
        get { defaults.float(forKey: Key.level) }
        set { defaults.set(newValue, forKey: Key.level) }
    }

    /// True when the app is running a session right now.
    public func appIsAlive(now: Date = Date()) -> Bool {
        guard snapshot.phase != .off, let heartbeat else { return false }
        return now.timeIntervalSince(heartbeat) < Self.heartbeatTimeout
    }

    // MARK: - Plumbing

    private func date(forKey key: String) -> Date? {
        let seconds = defaults.double(forKey: key)
        return seconds > 0 ? Date(timeIntervalSince1970: seconds) : nil
    }

    private func decode<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private func encode<T: Encodable>(_ value: T, forKey key: String) {
        guard let data = try? encoder.encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
