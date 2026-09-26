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
import CoreAudio
import VoiceIQCore

/// Owns the NSStatusItem. Plain NSStatusItem (not MenuBarExtra) so the template
/// icon can pulse for listening and processing states.
final class StatusItemController: NSObject {
    enum VisualState {
        case idle
        case listening
        case processing
        case attention // permission missing / key invalid
    }

    private let statusItem: NSStatusItem
    private let onOpenHistory: () -> Void
    private let onPasteLast: () -> Void
    private let onOpenSettings: () -> Void
    private let onStartHandsFree: () -> Void
    private let onOpenAbout: () -> Void
    private let templateImage: NSImage
    private var animationTimer: Timer?
    private var animationStartedAt = Date()
    private var state: VisualState = .idle

    init(
        onOpenHistory: @escaping () -> Void,
        onPasteLast: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onStartHandsFree: @escaping () -> Void,
        onOpenAbout: @escaping () -> Void
    ) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.onOpenHistory = onOpenHistory
        self.onPasteLast = onPasteLast
        self.onOpenSettings = onOpenSettings
        self.onStartHandsFree = onStartHandsFree
        self.onOpenAbout = onOpenAbout
        self.templateImage = Self.loadTemplateImage()
        super.init()

        statusItem.button?.image = templateImage
        statusItem.button?.toolTip = "Voice IQ"
        statusItem.menu = makeMenu()
    }

    func setState(_ newState: VisualState) {
        guard newState != state else { return }
        state = newState
        animationTimer?.invalidate()
        animationTimer = nil
        animationStartedAt = Date()

        switch newState {
        case .idle:
            statusItem.button?.alphaValue = 1
        case .attention:
            statusItem.button?.alphaValue = 0.4
        case .listening, .processing:
            // Pulse the button's alpha rather than redrawing the image: a fresh
            // NSImage per frame at 30 fps made the status item re-measure and
            // recommit its scene on every tick for the whole dictation.
            animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in
                self?.tickAnimation()
            }
            tickAnimation()
        }
    }

    private func tickAnimation() {
        let duration = state == .listening ? 0.7 : 1.2
        let phase = Date().timeIntervalSince(animationStartedAt) / duration * 2 * Double.pi
        statusItem.button?.alphaValue = 0.725 + 0.275 * CGFloat(sin(phase))
    }

    private static func loadTemplateImage() -> NSImage {
        guard let bundled = Bundle.main.image(forResource: "MenuBarIcon"),
              let image = bundled.copy() as? NSImage else { return NSImage(size: NSSize(width: 18, height: 18)) }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }

    // MARK: - Menu

    private var statusLine: NSMenuItem?

    func setStatusLine(_ text: String) {
        statusLine?.title = text
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()

        let status = NSMenuItem(title: "Starting up…", action: nil, keyEquivalent: "")
        status.isEnabled = false
        statusLine = status
        menu.addItem(status)

        menu.addItem(.separator())

        let handsFree = NSMenuItem(title: "Start Hands-Free Dictation", action: #selector(startHandsFree), keyEquivalent: "")
        handsFree.target = self
        menu.addItem(handsFree)

        let pasteLast = NSMenuItem(title: "Paste Last Transcript", action: #selector(pasteLastTranscript), keyEquivalent: "")
        pasteLast.target = self
        menu.addItem(pasteLast)

        let history = NSMenuItem(title: "History…", action: #selector(openHistory), keyEquivalent: "")
        history.target = self
        menu.addItem(history)

        menu.addItem(.separator())

        // Which mic Voice IQ hears through — moves the SYSTEM default input, exactly
        // like Control Center, so AirPods vs built-in is one click (dogfood).
        let micItem = NSMenuItem(title: "Microphone", action: nil, keyEquivalent: "")
        let micMenu = NSMenu(title: "Microphone")
        micMenu.delegate = self
        micItem.submenu = micMenu
        menu.addItem(micItem)

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let about = NSMenuItem(title: "About Voice IQ", action: #selector(openAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        let quit = NSMenuItem(title: "Quit Voice IQ", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        return menu
    }

    @objc private func openHistory() {
        onOpenHistory()
    }

    @objc private func openSettings() {
        onOpenSettings()
    }

    @objc private func startHandsFree() {
        onStartHandsFree()
    }

    @objc private func pasteLastTranscript() {
        onPasteLast()
    }

    @objc private func openAbout() {
        onOpenAbout()
    }

    @objc private func selectMicrophone(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? AudioDeviceID else { return }
        AudioInputDevices.setDefault(id: id)
    }
}

extension StatusItemController: NSMenuDelegate {
    /// Rebuild the Microphone submenu each open — devices come and go
    /// (AirPods connect, headsets unplug) and the checkmark must be live.
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu.title == "Microphone" else { return }
        menu.removeAllItems()
        let current = AudioInputDevices.currentDefaultID()
        let devices = AudioInputDevices.list()
        if devices.isEmpty {
            let none = NSMenuItem(title: "No microphones found", action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
            return
        }
        for device in devices {
            let item = NSMenuItem(title: device.name, action: #selector(selectMicrophone(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = device.id
            item.state = device.id == current ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let note = NSMenuItem(title: "Sets your Mac's input device", action: nil, keyEquivalent: "")
        note.isEnabled = false
        menu.addItem(note)
    }
}
