// Copyright 2026 Google LLC
// Licensed under the Apache License, Version 2.0.

import Foundation

public enum ShortcutAction: String, CaseIterable, Sendable {
    case pasteLastTranscript
    case askAnything
    case translate
    case meetingToggle
}

public extension Notification.Name {
    static let voiceIQShortcutDidChange = Notification.Name("voiceIQShortcutDidChange")
}

public final class ShortcutStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func shortcut(for action: ShortcutAction) -> KeyShortcut {
        if let data = defaults.data(forKey: key(for: action)),
           let shortcut = try? decoder.decode(KeyShortcut.self, from: data) {
            return shortcut
        }
        return Self.defaultShortcut(for: action)
    }

    public func set(_ shortcut: KeyShortcut, for action: ShortcutAction) {
        guard let data = try? encoder.encode(shortcut) else { return }
        defaults.set(data, forKey: key(for: action))
        NotificationCenter.default.post(name: .voiceIQShortcutDidChange, object: action)
    }

    public func reset(_ action: ShortcutAction) {
        defaults.removeObject(forKey: key(for: action))
        NotificationCenter.default.post(name: .voiceIQShortcutDidChange, object: action)
    }

    public static func defaultShortcut(for action: ShortcutAction) -> KeyShortcut {
        switch action {
        case .pasteLastTranscript:
            return KeyShortcut(keyCode: 9, modifiers: [.command, .shift])
        case .askAnything:
            return KeyShortcut(keyCode: 0, modifiers: [.control, .option])
        case .translate:
            return KeyShortcut(keyCode: 17, modifiers: [.control, .option])
        case .meetingToggle:
            return KeyShortcut(keyCode: 46, modifiers: [.option])
        }
    }

    private func key(for action: ShortcutAction) -> String {
        "shortcut.\(action.rawValue)"
    }
}
