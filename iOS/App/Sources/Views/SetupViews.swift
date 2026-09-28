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

import SwiftUI

/// Microphone, keyboard and (when off) Live Activities, on one page. Used by
/// onboarding and by Settings › Keyboard & Permissions.
struct PermissionsPanel: View {
    @EnvironmentObject private var setup: SetupMonitor

    var body: some View {
        let status = setup.status
        VStack(spacing: Theme.Spacing.m) {
            Card {
                HStack(spacing: Theme.Spacing.m) {
                    IconTile(systemImage: "mic.fill", size: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Microphone").font(Theme.Fonts.headline()).foregroundStyle(Theme.Colors.ink)
                        Text("Used only while you dictate or record a meeting.")
                            .font(Theme.Fonts.footnote()).foregroundStyle(Theme.Colors.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    if status.micGranted {
                        StatusChip(text: "Allowed", tone: .done)
                    } else if status.micDenied {
                        Button("Settings", action: openSettings).buttonStyle(.compactPrimary)
                    } else {
                        Button("Allow", action: setup.requestMicrophone).buttonStyle(.compactPrimary)
                    }
                }
            }

            Card {
                HStack(spacing: Theme.Spacing.m) {
                    IconTile(systemImage: "keyboard.fill", size: 32)
                    Text("VoiceiQ keyboard").font(Theme.Fonts.headline()).foregroundStyle(Theme.Colors.ink)
                    Spacer(minLength: 0)
                    if status.keyboardReady {
                        StatusChip(text: "Ready", tone: .done)
                    } else if status.keyboardAdded {
                        StatusChip(text: "Almost", tone: .pending)
                    }
                }
                SettingsMockup(keyboardOn: status.keyboardAdded, fullAccessOn: status.fullAccess)
                if status.keyboardAdded && !status.fullAccess {
                    Label("Full Access is confirmed the first time the VoiceiQ keyboard opens.", systemImage: "clock")
                        .font(Theme.Fonts.footnote())
                        .foregroundStyle(Theme.Colors.pending)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !status.keyboardReady {
                    Button("Open Settings", action: openSettings).buttonStyle(.primaryPill)
                }
            }

            if !status.liveActivitiesEnabled {
                Card {
                    HStack(spacing: Theme.Spacing.m) {
                        IconTile(systemImage: "circle.dashed.inset.filled", tint: Theme.Colors.pending, size: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Live Activities are off").font(Theme.Fonts.headline()).foregroundStyle(Theme.Colors.ink)
                            Text("The Action button needs them to dictate without opening VoiceiQ.")
                                .font(Theme.Fonts.footnote()).foregroundStyle(Theme.Colors.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    Button("Open Settings", action: openSettings).buttonStyle(.secondaryPill)
                }
            }
        }
    }

    private func openSettings() {
        UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
    }
}

/// A miniature of the Keyboards page in Settings with the two switches the
/// user must turn on, mirroring their real state.
private struct SettingsMockup: View {
    let keyboardOn: Bool
    let fullAccessOn: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Settings  ›  Apps  ›  VoiceiQ  ›  Keyboards")
                .font(Theme.Fonts.caption())
                .foregroundStyle(Theme.Colors.muted)
                .padding(.leading, 4)
            VStack(spacing: 0) {
                row("VoiceiQ", on: keyboardOn)
                Divider().padding(.leading, 12)
                row("Allow Full Access", on: fullAccessOn)
            }
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.Colors.surface))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.Colors.hairline, lineWidth: 0.5))
        }
        .padding(Theme.Spacing.m)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.Colors.surfaceNested))
        .accessibilityElement(children: .combine)
    }

    private func row(_ title: String, on: Bool) -> some View {
        HStack {
            Text(title).font(Theme.Fonts.subheadline()).foregroundStyle(Theme.Colors.ink)
            Spacer()
            Capsule()
                .fill(on ? Theme.Colors.success : Theme.Colors.porcelain)
                .frame(width: 38, height: 23)
                .overlay(alignment: on ? .trailing : .leading) {
                    Circle().fill(.white).frame(width: 19, height: 19).padding(2)
                        .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
                }
                .animation(.spring(response: 0.3), value: on)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}

/// A field to dictate into, with a live check that the keyboard ran with Full
/// Access. The keyboard can always be put away with Done or a drag.
struct TryItCard: View {
    @EnvironmentObject private var setup: SetupMonitor
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        Card {
            HStack {
                CheckLine(title: setup.status.fullAccess ? "VoiceiQ keyboard is working" : "Waiting for the VoiceiQ keyboard",
                          done: setup.status.fullAccess,
                          waiting: !setup.status.fullAccess)
                Spacer(minLength: Theme.Spacing.s)
                // In the header, not under the field: the keyboard's floating
                // Done button sits over the card's bottom-right corner.
                if !text.isEmpty {
                    Button("Clear") { text = "" }.buttonStyle(.compactSecondary)
                }
            }
            TextField("Try: “Remind me to call Sam at three, no, four pm.”", text: $text, axis: .vertical)
                .font(Theme.Fonts.body())
                .lineLimit(4...10)
                .focused($focused)
                .padding(Theme.Spacing.m)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.field, style: .continuous).fill(Theme.Colors.surfaceNested))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.field, style: .continuous)
                    .strokeBorder(focused ? Theme.Colors.accent : Theme.Colors.hairline, lineWidth: focused ? 1.5 : 0.5))
        }
    }
}

/// Settings › Keyboard & Permissions.
struct KeyboardSetupView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.xl) {
                PermissionsPanel()
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    GroupLabel(text: "Try it")
                    TryItCard()
                }
            }
            .padding(.horizontal, Theme.Spacing.page)
            .padding(.vertical, Theme.Spacing.l)
        }
        .keyboardDismissable()
        .themedBackground()
        .navigationTitle("Keyboard & Permissions")
        .navigationBarTitleDisplayMode(.inline)
    }
}
