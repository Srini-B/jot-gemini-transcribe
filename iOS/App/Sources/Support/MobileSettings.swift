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
import UIKit
import VoiceIQBridge

/// Settings that exist only on iOS. Everything shared with macOS lives in
/// `SettingsStore`.
enum MobileSettings {
    private static let defaults = UserDefaults.standard

    /// Record from the iPhone's microphone even when AirPods are connected, so
    /// their audio stays in high quality. Default on, like Typeless.
    static var preferBuiltInMic: Bool {
        get { defaults.object(forKey: "preferBuiltInMic") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "preferBuiltInMic") }
    }

    static var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: "mobileOnboardingDone") }
        set { defaults.set(newValue, forKey: "mobileOnboardingDone") }
    }

    static let keyboardBundleID = "io.blue.voiceiq.ios.keyboard"

    /// The keyboard is in Settings › General › Keyboard › Keyboards.
    static var keyboardAdded: Bool {
        (defaults.object(forKey: "AppleKeyboards") as? [String])?.contains(keyboardBundleID) ?? false
    }

    /// The keyboard has run with Full Access at least once. It can only write
    /// to the App Group when Full Access is on, so this is proof, not a guess.
    static var keyboardHasFullAccess: Bool {
        SharedStore.shared.keyboardSeenAt != nil
    }
}

/// Readable names for the bundle IDs the keyboard reports. iOS gives an app
/// no way to look up another app's name, so common ones are listed.
enum AppNames {
    private static let known: [String: String] = [
        "com.apple.mobilenotes": "Notes",
        "com.apple.MobileSMS": "Messages",
        "com.apple.mobilemail": "Mail",
        "com.apple.mobilesafari": "Safari",
        "com.apple.SafariViewService": "Safari",
        "com.apple.reminders": "Reminders",
        "com.apple.Spotlight": "Spotlight",
        "com.apple.Pages": "Pages",
        "com.apple.journal": "Journal",
        "net.whatsapp.WhatsApp": "WhatsApp",
        "com.tinyspeck.chatlyio": "Slack",
        "com.google.Gmail": "Gmail",
        "com.google.chrome.ios": "Chrome",
        "com.openai.chat": "ChatGPT",
        "com.anthropic.claude": "Claude",
        "com.google.gemini": "Gemini",
        "com.facebook.Messenger": "Messenger",
        "com.burbn.instagram": "Instagram",
        "com.atebits.Tweetie2": "X",
        "com.hammerandchisel.discord": "Discord",
        "org.whispersystems.signal": "Signal",
        "com.telegram.telegram-ios": "Telegram",
        "ph.telegra.Telegraph": "Telegram",
        "notion.id": "Notion",
        "com.linear.ios": "Linear",
        "com.microsoft.Office.Outlook": "Outlook",
        "com.microsoft.skype.teams": "Teams",
        "md.obsidian": "Obsidian",
    ]

    static func displayName(for bundleID: String) -> String {
        if let name = known[bundleID] { return name }
        let last = bundleID.split(separator: ".").last.map(String.init) ?? bundleID
        return last.prefix(1).uppercased() + last.dropFirst()
    }
}
