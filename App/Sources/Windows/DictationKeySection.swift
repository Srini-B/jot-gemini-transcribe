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

import AppKit
import AVFoundation
import VoiceIQCore
import SwiftUI

/// The dictation key, recorded by pressing it like the other shortcuts. Only
/// bare modifier keys qualify (fn, ⌘, ⌥, ⌃ on either side); the side is part
/// of the key, so the opposite twin never triggers.
struct DictationKeySection: View {
    private let settings = SettingsStore()
    @State private var hotkey = SettingsStore().hotkeyKey
    @State private var doubleTapLock = SettingsStore().doubleTapLockEnabled
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Section("Dictation key") {
            LabeledContent("Hold to dictate") {
                HStack(spacing: 8) {
                    Button(isRecording ? "Press a key…" : hotkey.displayName) {
                        isRecording ? stopRecording() : startRecording()
                    }
                    .buttonStyle(.bordered)
                    .clipShape(Capsule())
                    .controlSize(.small)

                    Button {
                        apply(.fn)
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .buttonStyle(.plain)
                    .help("Reset to fn")
                }
            }
            Toggle("Double-tap to lock hands-free", isOn: $doubleTapLock)
                .onChange(of: doubleTapLock) { _, enabled in
                    guard enabled != settings.doubleTapLockEnabled else { return }
                    settings.setDoubleTapLock(enabled)
                }
        }
        .onAppear {
            hotkey = settings.hotkeyKey
            doubleTapLock = settings.doubleTapLockEnabled
        }
        .onDisappear { stopRecording() }
        .onReceive(NotificationCenter.default.publisher(for: .gtSettingDidChange).receive(on: RunLoop.main)) { note in
            switch note.object as? String {
            case "hotkeyKey": hotkey = settings.hotkeyKey
            case "doubleTapLock": doubleTapLock = settings.doubleTapLockEnabled
            default: break
            }
        }
    }

    private func apply(_ key: HotkeyKey) {
        settings.setHotkeyKey(key)
        hotkey = key
    }

    private func startRecording() {
        stopRecording()
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if event.type == .keyDown, event.keyCode == 53 {
                stopRecording()
                return nil
            }
            guard event.type == .flagsChanged, let key = HotkeyKey(keyCode: Int64(event.keyCode)) else { return event }
            // Modifier keys report a flagsChanged on press and again on release;
            // the press is the one where the key's own flag is set.
            guard key.isDown(in: CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue))) else { return nil }
            apply(key)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
    }
}

/// Live status of the permissions dictation depends on. A revoked grant used
/// to be visible only from the menu bar; here each row opens the matching
/// System Settings pane and updates on its own once the grant lands.
struct PermissionsSection: View {
    @State private var accessibility = AXIsProcessTrusted()
    @State private var screenRecording = CGPreflightScreenCaptureAccess()
    @State private var microphone = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized

    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Section("Permissions") {
            PermissionRow(title: "Accessibility", granted: accessibility, settingsAnchor: "Privacy_Accessibility")
            PermissionRow(title: "Screen Recording", granted: screenRecording, settingsAnchor: "Privacy_ScreenCapture")
            PermissionRow(title: "Microphone", granted: microphone, settingsAnchor: "Privacy_Microphone")
        }
        .onReceive(poll) { _ in refresh() }
        .onAppear { refresh() }
    }

    private func refresh() {
        accessibility = AXIsProcessTrusted()
        screenRecording = CGPreflightScreenCaptureAccess()
        microphone = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }
}

private struct PermissionRow: View {
    let title: String
    let granted: Bool
    let settingsAnchor: String

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(granted ? VoiceIQUI.Colors.success : VoiceIQUI.Colors.error)
                Text(granted ? "Granted" : "Not granted")
                    .foregroundStyle(.secondary)
                if !granted {
                    Button("Open System Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(settingsAnchor)")!)
                    }
                    .controlSize(.small)
                }
            }
        }
    }
}
