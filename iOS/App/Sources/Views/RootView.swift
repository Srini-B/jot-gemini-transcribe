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

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @State private var onboarded = MobileSettings.hasCompletedOnboarding
    @State private var tab = Tab.home
    @State private var showKeyboardSetup = false

    enum Tab { case home, history, meetings, settings }

    var body: some View {
        Group {
            if onboarded {
                TabView(selection: $tab) {
                    HomeView()
                        .tabItem { Label("Home", systemImage: "mic") }
                        .tag(Tab.home)
                    HistoryView()
                        .tabItem { Label("History", systemImage: "clock") }
                        .tag(Tab.history)
                    MeetingsView()
                        .tabItem { Label("Meetings", systemImage: "person.2.wave.2") }
                        .tag(Tab.meetings)
                    SettingsView()
                        .tabItem { Label("Settings", systemImage: "gearshape") }
                        .tag(Tab.settings)
                }
            } else {
                OnboardingView {
                    MobileSettings.hasCompletedOnboarding = true
                    onboarded = true
                }
            }
        }
        .overlay {
            if model.showSwipeBack {
                SwipeBackView()
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .top) {
            if let banner = model.banner {
                BannerView(text: banner) { model.banner = nil }
                    .padding(.horizontal)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.showSwipeBack)
        .animation(.easeInOut(duration: 0.2), value: model.banner)
        .sheet(isPresented: $showKeyboardSetup) {
            NavigationStack { KeyboardSetupView() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .voiceIQShowKeyboardSetup)) { _ in
            if onboarded { showKeyboardSetup = true }
        }
    }
}

/// Shown after the one-time bounce when the app could not send the user back.
struct SwipeBackView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThickMaterial).ignoresSafeArea()
            VStack(spacing: 20) {
                Spacer()
                Image(systemName: "mic.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Brand.recording)
                Text("Listening")
                    .font(.title.bold())
                Text("Swipe right along the bottom edge to go back")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Spacer()
                SwipeHint()
                    .padding(.bottom, 24)
            }
            .padding(32)
        }
        .onTapGesture { model.showSwipeBack = false }
    }
}

private struct SwipeHint: View {
    @State private var offset: CGFloat = -60

    var body: some View {
        Capsule()
            .fill(Color.secondary.opacity(0.5))
            .frame(width: 140, height: 6)
            .overlay(alignment: .leading) {
                Image(systemName: "hand.point.up.left.fill")
                    .font(.title)
                    .offset(x: offset + 50, y: -24)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false)) { offset = 60 }
            }
    }
}

struct BannerView: View {
    let text: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            Text(text).font(.subheadline)
            Spacer(minLength: 8)
            Button(action: dismiss) { Image(systemName: "xmark").font(.caption.bold()) }
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(.regularMaterial))
        .shadow(radius: 4, y: 2)
        .task {
            try? await Task.sleep(for: .seconds(5))
            dismiss()
        }
    }
}
