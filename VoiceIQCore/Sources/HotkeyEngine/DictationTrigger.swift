// Copyright 2026 Google LLC
// Licensed under the Apache License, Version 2.0.

import Foundation

/// What starts and stops a dictation: a bare modifier key (fn, a sided ⌘ ⌥ ⌃)
/// or a modifier-plus-key combination like the other shortcuts. Both are a
/// tap, never a hold.
public enum DictationTrigger: Codable, Equatable, Sendable {
    case modifier(HotkeyKey)
    case combo(KeyShortcut)

    public static let `default`: DictationTrigger = .modifier(.fn)

    public var displayName: String {
        switch self {
        case .modifier(let key): return key.displayName
        case .combo(let shortcut): return shortcut.displayString
        }
    }

    /// True for the bare-modifier form, whose side is part of the key itself.
    public var isModifier: Bool {
        if case .modifier = self { return true }
        return false
    }
}
