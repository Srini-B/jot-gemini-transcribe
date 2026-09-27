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
import UIKit
import VoiceIQBridge

/// Voice only: a mode switch, one microphone button, and the few keys a
/// dictation needs around it. No letters.
struct KeyboardView: View {
    @ObservedObject var model: KeyboardModel
    let controller: KeyboardViewController

    /// Brand blue, lighter on a dark keyboard.
    static let accent = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.341, green: 0.525, blue: 0.941, alpha: 1)
            : UIColor(red: 0.133, green: 0.322, blue: 0.737, alpha: 1)
    })
    static let recording = Color(red: 0.92, green: 0.26, blue: 0.21)

    var body: some View {
        VStack(spacing: 8) {
            if let answer = model.answer {
                AnswerPanel(answer: answer, model: model)
            } else {
                ModePicker(mode: $model.mode, locked: model.phase == .recording || model.phase == .processing)
                Spacer(minLength: 0)
                center
                Spacer(minLength: 0)
            }
            bottomRow
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    @ViewBuilder private var center: some View {
        if !model.hasFullAccess {
            Button("Allow Full Access") { model.micTapped() }
                .buttonStyle(.borderedProminent)
                .tint(Self.accent)
            Text("Settings › VoiceiQ › Keyboards")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 28) {
                cancelButton
                MicButton(phase: model.phase, waiting: model.waitingForApp, level: model.level) {
                    model.micTapped()
                }
                Color.clear.frame(width: 36, height: 36)
            }
            Text(statusText)
                .font(.footnote.weight(.medium))
                .foregroundStyle(model.notice == nil ? Color.secondary : Self.recording)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(minHeight: 18)
        }
    }

    @ViewBuilder private var cancelButton: some View {
        if model.phase == .recording {
            Button(action: model.cancelTapped) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color(.secondarySystemFill)))
            }
            .foregroundStyle(.primary)
            .accessibilityLabel("Cancel")
        } else {
            Color.clear.frame(width: 36, height: 36)
        }
    }

    private var statusText: String {
        if let notice = model.notice { return notice }
        if model.waitingForApp, model.phase != .recording { return "Starting…" }
        switch model.phase {
        case .recording: return "Listening"
        case .processing: return model.mode == .ask ? "Thinking" : "Writing"
        case .warm, .off: return "Tap to \(model.mode.title.lowercased())"
        }
    }

    private var bottomRow: some View {
        HStack(spacing: 6) {
            if model.showsGlobeKey {
                GlobeKey(controller: controller)
                    .frame(width: 44)
            }
            KeyCap(systemImage: "doc.on.clipboard", label: "Paste last", enabled: model.lastText != nil) {
                model.pasteLast()
            }
            .frame(width: 44)
            KeyCap(title: "space") { model.insertSpace() }
            RepeatingKey(action: model.deleteBackward)
                .frame(width: 52)
            KeyCap(systemImage: "return", label: "Return") { model.insertReturn() }
                .frame(width: 52)
        }
        .frame(height: 42)
    }
}

// MARK: - Pieces

private struct ModePicker: View {
    @Binding var mode: KeyboardMode
    let locked: Bool

    var body: some View {
        HStack(spacing: 6) {
            ForEach(KeyboardMode.allCases, id: \.self) { item in
                Button {
                    mode = item
                } label: {
                    Label(item.title, systemImage: item.symbol)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(mode == item ? KeyboardView.accent.opacity(0.18) : Color(.tertiarySystemFill)))
                        .foregroundStyle(mode == item ? KeyboardView.accent : .primary)
                }
                .disabled(locked)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct MicButton: View {
    let phase: SessionSnapshot.Phase
    let waiting: Bool
    let level: Float
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if phase == .recording {
                    Circle()
                        .fill(KeyboardView.recording.opacity(0.18))
                        .frame(width: 84, height: 84)
                        .scaleEffect(1 + CGFloat(min(level, 1)) * 0.35)
                        .animation(.easeOut(duration: 0.12), value: level)
                }
                Circle()
                    .fill(phase == .recording ? KeyboardView.recording : KeyboardView.accent)
                    .frame(width: 72, height: 72)
                    .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                icon
            }
            .frame(width: 96, height: 96)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(phase == .recording ? "Stop" : "Dictate")
    }

    @ViewBuilder private var icon: some View {
        switch phase {
        case .recording:
            RoundedRectangle(cornerRadius: 5).fill(.white).frame(width: 22, height: 22)
        case .processing:
            ProgressView().tint(.white)
        case .warm, .off:
            if waiting {
                ProgressView().tint(.white)
            } else {
                Image(systemName: "mic.fill").font(.system(size: 28, weight: .semibold)).foregroundStyle(.white)
            }
        }
    }
}

private struct AnswerPanel: View {
    let answer: Delivery
    @ObservedObject var model: KeyboardModel

    var body: some View {
        VStack(spacing: 8) {
            ScrollView {
                Text(answer.text)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            HStack {
                Button("Close", action: model.dismissAnswer)
                Spacer()
                Button("Copy", action: model.copyAnswer)
                Button("Insert", action: model.insertAnswer)
                    .buttonStyle(.borderedProminent)
                    .tint(KeyboardView.accent)
            }
            .font(.callout.weight(.semibold))
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
    }
}

private struct KeyCap: View {
    var title: String?
    var systemImage: String?
    var label: String?
    var enabled = true
    let action: () -> Void

    init(title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    init(systemImage: String, label: String, enabled: Bool = true, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.label = label
        self.enabled = enabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Group {
                if let systemImage { Image(systemName: systemImage) } else { Text(title ?? "") }
            }
            .font(.system(size: 16, weight: .regular))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(.systemBackground).opacity(0.9)))
            .shadow(color: .black.opacity(0.25), radius: 0, y: 1)
        }
        .foregroundStyle(.primary)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityLabel(label ?? title ?? "")
    }
}

/// The system's globe key. Needs the UIKit action to show the keyboard list.
private struct GlobeKey: UIViewRepresentable {
    let controller: KeyboardViewController

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "globe"), for: .normal)
        button.tintColor = .label
        button.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.9)
        button.layer.cornerRadius = 6
        button.accessibilityLabel = "Next keyboard"
        button.addTarget(controller, action: #selector(UIInputViewController.handleInputModeList(from:with:)), for: .allTouchEvents)
        return button
    }

    func updateUIView(_ uiView: UIButton, context: Context) {}
}

/// Delete that repeats while held, like the system key.
private struct RepeatingKey: UIViewRepresentable {
    let action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "delete.left"), for: .normal)
        button.tintColor = .label
        button.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.9)
        button.layer.cornerRadius = 6
        button.accessibilityLabel = "Delete"
        button.addTarget(context.coordinator, action: #selector(Coordinator.down), for: .touchDown)
        button.addTarget(context.coordinator, action: #selector(Coordinator.up), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        return button
    }

    func updateUIView(_ uiView: UIButton, context: Context) {
        context.coordinator.action = action
    }

    final class Coordinator: NSObject {
        var action: () -> Void
        private var timer: Timer?

        init(action: @escaping () -> Void) { self.action = action }

        @objc func down() {
            action()
            timer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
                self?.timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in self?.action() }
            }
        }

        @objc func up() {
            timer?.invalidate()
            timer = nil
        }
    }
}
