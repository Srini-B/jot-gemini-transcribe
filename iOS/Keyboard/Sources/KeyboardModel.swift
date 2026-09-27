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

/// The keyboard's side of the bridge. It never records or talks to a model:
/// it sends commands to the app and inserts what comes back.
@MainActor
final class KeyboardModel: ObservableObject {
    @Published private(set) var snapshot = SessionSnapshot()
    @Published private(set) var appAlive = false
    @Published private(set) var level: Float = 0
    @Published private(set) var answer: Delivery?
    @Published private(set) var notice: String?
    @Published private(set) var waitingForApp = false
    @Published private(set) var hasFullAccess = true
    /// Read once per appearance: UIKit answers wrongly before the host connects.
    @Published private(set) var showsGlobeKey = true
    @Published var mode: KeyboardMode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: Self.modeKey) }
    }

    /// When the app has not acknowledged a command by then, it is asleep:
    /// open it. The app answers in well under 100 ms when it is running.
    static let acknowledgementTimeout: TimeInterval = 0.7
    /// A dictation finished longer ago than this is not typed into whatever
    /// field happens to be open now; it stays available behind Paste last.
    static let autoInsertWindow: TimeInterval = 120
    private static let modeKey = "keyboardMode"

    weak var controller: KeyboardViewController?
    private let store = SharedStore.shared
    private var observer: UUID?
    private var timer: Timer?
    private var pendingCommandID: UUID?
    private var pendingSince: Date?
    private var shownNoticeID: UUID?

    init() {
        mode = UserDefaults.standard.string(forKey: Self.modeKey).flatMap(KeyboardMode.init(rawValue:)) ?? .dictate
    }

    /// The session phase, trusting the snapshot only while the app is alive.
    var phase: SessionSnapshot.Phase { appAlive ? snapshot.phase : .off }

    var lastText: String? { snapshot.delivery?.text }

    // MARK: - Lifecycle

    func appeared() {
        hasFullAccess = controller?.hasFullAccess ?? false
        if hasFullAccess { store.keyboardSeenAt = Date() }
        observer = DarwinNotifier.observe(.state) { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        refresh()
    }

    func refreshHostTraits() {
        let needsGlobe = controller?.needsInputModeSwitchKey ?? true
        if needsGlobe != showsGlobeKey { showsGlobeKey = needsGlobe }
    }

    func disappeared() {
        if let observer { DarwinNotifier.removeObserver(observer) }
        observer = nil
        timer?.invalidate()
        timer = nil
    }

    /// Darwin pings are dropped while a process is suspended, so the keyboard
    /// also polls while it is on screen. Reads are local and cheap.
    private func tick() {
        refresh()
        let newLevel = phase == .recording ? store.level : 0
        if newLevel != level { level = newLevel }
    }

    private func refresh() {
        let fresh = store.snapshot
        if fresh != snapshot { snapshot = fresh }
        let alive = store.appIsAlive()
        if alive != appAlive { appAlive = alive }
        if let pendingCommandID, store.handledCommandID == pendingCommandID {
            self.pendingCommandID = nil
            waitingForApp = false
        }
        if waitingForApp, let pendingSince, Date().timeIntervalSince(pendingSince) > 12 {
            waitingForApp = false
            pendingCommandID = nil
        }
        deliverIfNeeded()
        showNoticeIfNeeded()
    }

    // MARK: - Actions

    func micTapped() {
        guard hasFullAccess else {
            controller?.openURL(BridgeURL.setup)
            return
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        switch phase {
        case .recording:
            send(KeyboardCommand(action: .stop, mode: mode))
        case .processing:
            break
        case .warm, .off:
            start()
        }
    }

    func cancelTapped() {
        guard phase == .recording else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        send(KeyboardCommand(action: .cancel, mode: mode))
    }

    func pasteLast() {
        guard let lastText else { return }
        insert(lastText)
    }

    func insertAnswer() {
        guard let answer else { return }
        insert(answer.text)
        dismissAnswer()
    }

    func copyAnswer() {
        guard let answer else { return }
        UIPasteboard.general.string = answer.text
        dismissAnswer()
    }

    func dismissAnswer() {
        if let answer { store.insertedDeliveryID = answer.id }
        answer = nil
    }

    private func start() {
        let host = controller.flatMap(HostAppResolver.currentHost(for:))
        let context = mode == .ask ? controller?.textDocumentProxy.selectedText : nil
        let command = KeyboardCommand(action: .start, mode: mode, context: context, hostBundleID: host)
        let alive = appAlive
        send(command)
        waitingForApp = true
        pendingCommandID = command.id
        pendingSince = Date()
        guard alive else {
            openApp(for: command)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.acknowledgementTimeout) { [weak self] in
            guard let self, self.pendingCommandID == command.id,
                  self.store.handledCommandID != command.id else { return }
            self.openApp(for: command)
        }
    }

    private func send(_ command: KeyboardCommand) {
        store.append(command)
    }

    private func openApp(for command: KeyboardCommand) {
        controller?.openURL(BridgeURL.start(commandID: command.id, host: command.hostBundleID))
    }

    // MARK: - Results

    private func deliverIfNeeded() {
        guard let delivery = snapshot.delivery, delivery.id != store.insertedDeliveryID else { return }
        if delivery.mode == .ask {
            if answer?.id != delivery.id { answer = delivery }
            return
        }
        store.insertedDeliveryID = delivery.id
        guard Date().timeIntervalSince(delivery.createdAt) < Self.autoInsertWindow else { return }
        // Finished for another app (the user moved on mid-dictation): never
        // type it into this one. Paste last still has it.
        if let origin = delivery.hostBundleID,
           let here = controller.flatMap(HostAppResolver.currentHost(for:)), origin != here {
            return
        }
        insert(delivery.text)
    }

    private func showNoticeIfNeeded() {
        guard let fresh = snapshot.notice, fresh.id != shownNoticeID,
              Date().timeIntervalSince(fresh.createdAt) < 10 else { return }
        shownNoticeID = fresh.id
        notice = fresh.text
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            if self?.notice == fresh.text { self?.notice = nil }
        }
    }

    /// Adds a space when the new text would otherwise run into the previous word.
    private func insert(_ text: String) {
        guard let proxy = controller?.textDocumentProxy, !text.isEmpty else { return }
        var output = text
        if let previous = proxy.documentContextBeforeInput?.last, !previous.isWhitespace,
           let first = text.first, !first.isWhitespace, !first.isPunctuation {
            output = " " + output
        }
        proxy.insertText(output)
    }

    // MARK: - Keys

    func deleteBackward() {
        controller?.textDocumentProxy.deleteBackward()
    }

    func insertSpace() {
        controller?.textDocumentProxy.insertText(" ")
    }

    func insertReturn() {
        controller?.textDocumentProxy.insertText("\n")
    }
}
