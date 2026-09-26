// Copyright 2026 Google LLC
// Licensed under the Apache License, Version 2.0.

import AppKit
import VoiceIQCore
import SwiftUI

struct ShortcutRecorderRow: View {
    let title: String
    let action: ShortcutAction

    private let store = ShortcutStore()
    @State private var shortcut: KeyShortcut
    @State private var isRecording = false
    @State private var monitor: Any?

    init(title: String, action: ShortcutAction) {
        self.title = title
        self.action = action
        _shortcut = State(initialValue: ShortcutStore().shortcut(for: action))
    }

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                Button(isRecording ? "Press keys…" : shortcut.displayString) {
                    isRecording ? stopRecording() : startRecording()
                }
                .buttonStyle(.bordered)
                .clipShape(Capsule())
                .controlSize(.small)

                Text("Side")
                Picker("Side", selection: sideBinding) {
                    ForEach(KeyShortcut.Side.allCases, id: \.self) { side in
                        Text(side.displayName).tag(side)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 74)

                Button {
                    store.reset(action)
                    shortcut = store.shortcut(for: action)
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.plain)
                .help("Reset shortcut")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .voiceIQShortcutDidChange)) { note in
            guard note.object as? ShortcutAction == action else { return }
            shortcut = store.shortcut(for: action)
        }
        .onDisappear { stopRecording() }
    }

    private var sideBinding: Binding<KeyShortcut.Side> {
        Binding(
            get: { shortcut.side },
            set: { side in
                let updated = KeyShortcut(
                    keyCode: shortcut.keyCode,
                    modifiers: shortcut.modifiers,
                    side: side
                )
                store.set(updated, for: action)
                shortcut = updated
            }
        )
    }

    private func startRecording() {
        stopRecording()
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            guard event.type == .keyDown else { return event }
            if event.keyCode == 53 {
                stopRecording()
                return nil
            }

            let modifiers = Self.modifiers(from: event.modifierFlags)
            guard !modifiers.isEmpty else { return nil }
            let side = Self.side(for: modifiers, rawFlags: event.modifierFlags.rawValue)
            let updated = KeyShortcut(keyCode: event.keyCode, modifiers: modifiers, side: side)
            store.set(updated, for: action)
            shortcut = updated
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
    }

    private static func modifiers(from flags: NSEvent.ModifierFlags) -> Set<KeyShortcut.Modifier> {
        var result: Set<KeyShortcut.Modifier> = []
        if flags.contains(.command) { result.insert(.command) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.shift) { result.insert(.shift) }
        return result
    }

    private static func side(
        for modifiers: Set<KeyShortcut.Modifier>,
        rawFlags: UInt
    ) -> KeyShortcut.Side {
        let raw = UInt64(rawFlags)
        let masks: [KeyShortcut.Modifier: (left: UInt64, right: UInt64)] = [
            .command: (0x0008, 0x0010),
            .option: (0x0020, 0x0040),
            .control: (0x0001, 0x2000),
            .shift: (0x0002, 0x0004),
        ]
        let allLeft = modifiers.allSatisfy { raw & masks[$0]!.left != 0 && raw & masks[$0]!.right == 0 }
        if allLeft { return .left }
        let allRight = modifiers.allSatisfy { raw & masks[$0]!.right != 0 && raw & masks[$0]!.left == 0 }
        return allRight ? .right : .either
    }
}
