// Copyright 2026 Google LLC
// Licensed under the Apache License, Version 2.0.

import Foundation

/// Process-wide "a Settings row is recording a shortcut" flag.
///
/// Both event taps read it on every key event and pass the event through
/// while it is set, so pressing the dictation key or Option-M to record it
/// reaches the Settings window's local monitor instead of starting a session.
/// One owner at a time: beginning a capture posts
/// `voiceIQShortcutCaptureDidBegin` so any other row still listening stops.
public enum ShortcutCapture {
    private static let lock = NSLock()
    private static var owner: UUID?

    public static var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return owner != nil
    }

    public static func begin(owner id: UUID) {
        lock.lock()
        owner = id
        lock.unlock()
        NotificationCenter.default.post(name: .voiceIQShortcutCaptureDidBegin, object: id)
    }

    /// Clears the flag only if `id` still owns it, so a row that lost the
    /// capture to another row cannot end that row's capture on disappear.
    public static func end(owner id: UUID) {
        lock.lock()
        if owner == id { owner = nil }
        lock.unlock()
    }
}

public extension Notification.Name {
    static let voiceIQShortcutCaptureDidBegin = Notification.Name("io.blue.voiceiq.shortcutCaptureDidBegin")
}
