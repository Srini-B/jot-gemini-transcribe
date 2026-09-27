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
import VoiceIQCore

/// The background voice session: keep-alive audio, the Live Activity, and
/// everything the keyboard reads from the App Group.
///
/// It ends only when the user ends it (Dynamic Island, app), when the Live
/// Activity goes away, or when iOS takes the audio session and will not give
/// it back. Stopping a dictation or dismissing the keyboard does not end it.
@MainActor
final class VoiceSession: ObservableObject {
    @Published private(set) var isActive = false

    /// What the dictation pipeline is doing. Set by the app model.
    var dictationPhase: SessionSnapshot.Phase = .warm { didSet { publishIfChanged() } }
    var mode: KeyboardMode = .dictate { didSet { publishIfChanged() } }
    var recordingStartedAt: Date? { didSet { publishIfChanged() } }
    var meetingStartedAt: Date? { didSet { publishIfChanged() } }

    var onInterruptionBegan: (() -> Void)?

    private let audio = KeepAliveAudio()
    private let activity = LiveActivityController()
    private let store = SharedStore.shared
    private var heartbeat: Timer?
    private var delivery: Delivery?
    private var notice: Notice?
    private var lastPublished: SessionSnapshot?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    init() {
        LiveActivityController.endLeftovers()
        // Whatever an earlier process left in the App Group is stale.
        delivery = store.snapshot.delivery
        publish(force: true)
        audio.onInterruptionBegan = { [weak self] in self?.onInterruptionBegan?() }
        audio.onLost = { [weak self] message in
            self?.post(notice: message)
            self?.end()
        }
        activity.onEndedOutsideApp = { [weak self] in
            Log.session.info("live activity ended outside the app — ending session")
            self?.end()
        }
    }

    /// Starts the session. Must run while the app is in the foreground.
    func begin() throws {
        guard !isActive else { return }
        try audio.start(preferBuiltInMic: MobileSettings.preferBuiltInMic)
        isActive = true
        activity.start(activityState)
        heartbeat = Timer.scheduledTimer(withTimeInterval: SharedStore.heartbeatInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.beat() }
        }
        beat()
        publish(force: true)
        Log.session.info("voice session began")
    }

    func end() {
        guard isActive else { return }
        isActive = false
        heartbeat?.invalidate()
        heartbeat = nil
        store.heartbeat = nil
        store.level = 0
        audio.stop()
        activity.end()
        publish(force: true)
        Log.session.info("voice session ended")
    }

    func setPreferBuiltInMic(_ prefer: Bool) {
        audio.setPreferBuiltInMic(prefer)
    }

    // MARK: - Results for the keyboard

    func deliver(_ delivery: Delivery) {
        self.delivery = delivery
        publish(force: true)
    }

    func post(notice text: String) {
        notice = Notice(text: text)
        publish(force: true)
    }

    func setLevel(_ level: Float) {
        guard isActive else { return }
        store.level = level
    }

    // MARK: - Background time

    /// Transcription can outlive the session (the user ended it mid-dictation,
    /// or a call interrupted it). Ask iOS for time to finish the request.
    func holdBackgroundTime() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Finish transcription") { [weak self] in
            self?.releaseBackgroundTime()
        }
    }

    func releaseBackgroundTime() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    // MARK: - Publishing

    private var snapshot: SessionSnapshot {
        SessionSnapshot(
            phase: isActive ? dictationPhase : .off,
            mode: mode,
            recordingStartedAt: recordingStartedAt,
            delivery: delivery,
            notice: notice,
            meetingActive: meetingStartedAt != nil
        )
    }

    private var activityState: VoiceSessionAttributes.ContentState {
        if let meetingStartedAt {
            return .init(phase: .meeting, mode: mode, since: meetingStartedAt)
        }
        switch dictationPhase {
        case .recording: return .init(phase: .recording, mode: mode, since: recordingStartedAt)
        case .processing: return .init(phase: .processing, mode: mode)
        case .warm, .off: return .init(phase: .ready, mode: mode)
        }
    }

    private func publishIfChanged() {
        publish(force: false)
    }

    private func publish(force: Bool) {
        let current = snapshot
        guard force || current != lastPublished else { return }
        lastPublished = current
        store.publish(current)
        if isActive { activity.update(activityState) }
    }

    private func beat() {
        store.heartbeat = Date()
    }
}
