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

/// Welcome, keys, permissions, try it. The page is saved as the user moves,
/// because iOS may end the app while they are in Settings.
struct OnboardingView: View {
    let onFinished: () -> Void
    @EnvironmentObject private var setup: SetupMonitor
    @State private var step = Step(rawValue: MobileSettings.onboardingStep) ?? .welcome
    @State private var forward = true
    /// The CTAs hide while typing: with the keyboard's Done bar above them they
    /// covered the key field the scroll view had just brought into view.
    @State private var keyboardShown = false

    enum Step: Int, CaseIterable { case welcome, keys, permissions, tryIt }

    var body: some View {
        VStack(spacing: 0) {
            if step != .welcome {
                OnboardingHeader(step: step.rawValue, total: Step.allCases.count - 1, back: back)
                    .padding(.horizontal, Theme.Spacing.page)
                    .padding(.top, Theme.Spacing.s)
            }
            ScrollView {
                page
                    .padding(.horizontal, Theme.Spacing.page)
                    .padding(.top, step == .welcome ? 0 : Theme.Spacing.xl)
                    .padding(.bottom, Theme.Spacing.xl)
                    .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .keyboardDismissable()
            if !keyboardShown {
                footer
                    .padding(.horizontal, Theme.Spacing.page)
                    .padding(.top, Theme.Spacing.m)
                    .padding(.bottom, Theme.Spacing.s)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardShown = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardShown = false
        }
        .background(Theme.Colors.canvas.ignoresSafeArea())
        .onTapGesture { UIApplication.shared.endEditing() }
        .onAppear { setup.refresh() }
        .animation(.easeInOut(duration: 0.25), value: step)
    }

    @ViewBuilder private var page: some View {
        Group {
            switch step {
            case .welcome: WelcomePage()
            case .keys: KeysPage()
            case .permissions: PermissionsPage()
            case .tryIt: TryItPage()
            }
        }
        .id(step)
        .transition(.asymmetric(
            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
            removal: .opacity
        ))
    }

    @ViewBuilder private var footer: some View {
        let status = setup.status
        VStack(spacing: Theme.Spacing.s) {
            switch step {
            case .welcome:
                Button("Get started", action: advance).buttonStyle(.primaryPill)
            case .keys:
                Button("Continue", action: advance).buttonStyle(.primaryPill)
                    .disabled(!status.hasKey)
                if !status.hasKey {
                    Button("Add a key later", action: advance).buttonStyle(.secondaryPill)
                }
            case .permissions:
                Button("Continue", action: advance).buttonStyle(.primaryPill)
                    .disabled(!(status.micGranted && status.keyboardAdded))
                if !(status.micGranted && status.keyboardAdded) {
                    Button("Set up later", action: advance).buttonStyle(.secondaryPill)
                }
            case .tryIt:
                Button("Start using VoiceiQ", action: finish).buttonStyle(.primaryPill)
            }
        }
    }

    private func advance() {
        UIApplication.shared.endEditing()
        guard let next = Step(rawValue: step.rawValue + 1) else { return finish() }
        forward = true
        step = next
        MobileSettings.onboardingStep = next.rawValue
    }

    private func back() {
        UIApplication.shared.endEditing()
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        forward = false
        step = previous
        MobileSettings.onboardingStep = previous.rawValue
    }

    private func finish() {
        MobileSettings.onboardingStep = 0
        onFinished()
    }
}

/// Back button and a segmented bar: one segment per setup page, filled up to
/// the current one.
private struct OnboardingHeader: View {
    let step: Int
    let total: Int
    let back: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.l) {
            Button(action: back) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.Colors.ink)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Theme.Colors.porcelain))
            }
            .accessibilityLabel("Back")
            HStack(spacing: 6) {
                ForEach(1...total, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? Theme.Colors.accent : Theme.Colors.hairline)
                        .frame(height: 4)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Step \(step) of \(total)")
            Color.clear.frame(width: 36, height: 36)
        }
    }
}

// MARK: - Pages

private struct WelcomePage: View {
    @State private var appeared = false

    var body: some View {
        VStack(spacing: Theme.Spacing.xxl) {
            Spacer(minLength: 56)
            VStack(spacing: Theme.Spacing.xl) {
                Wordmark(height: 52)
                    .scaleEffect(appeared ? 1 : 0.9)
                    .opacity(appeared ? 1 : 0)
                Text("Speak in any app.\nVoiceiQ types it.")
                    .font(Theme.Fonts.display())
                    .foregroundStyle(Theme.Colors.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                FeatureLine(symbol: "mic.fill", text: "Tap the mic on the VoiceiQ keyboard, wherever you type.")
                FeatureLine(symbol: "text.badge.checkmark", text: "Punctuation, lists and corrections come out right.")
                FeatureLine(symbol: "key.fill", text: "Runs on your own API key, kept on your iPhone.")
            }
            .padding(.horizontal, Theme.Spacing.s)
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { appeared = true }
        }
    }
}

private struct FeatureLine: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            IconTile(systemImage: symbol, size: 32)
            Text(text)
                .font(Theme.Fonts.callout())
                .foregroundStyle(Theme.Colors.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
        }
    }
}

private struct KeysPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            PageTitle(title: "Connect a model", detail: "VoiceiQ runs on your own API key.")
            ModelKeysForm()
        }
    }
}

private struct PermissionsPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            PageTitle(title: "Allow the microphone and keyboard")
            PermissionsPanel()
        }
    }
}

private struct TryItPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            PageTitle(title: "Try it",
                      detail: "Tap the box, hold the globe key to switch to VoiceiQ, then tap the mic.")
            TryItCard()
        }
    }
}
