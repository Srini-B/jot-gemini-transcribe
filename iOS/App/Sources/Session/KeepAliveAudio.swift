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

import AVFoundation
import VoiceIQCore

/// Keeps the app running in the background between dictations without the
/// microphone.
///
/// iOS suspends a backgrounded app unless it is playing or recording. Recording
/// the whole time would light the orange mic indicator; instead a playback-only
/// engine loops silence. It never touches `inputNode`, so the input unit stays
/// off. Because the `.playAndRecord` session is already active and the app is
/// running, a dictation can start the mic from the background on demand.
///
/// The session must be started while the app is in the foreground: iOS refuses
/// to activate an audio session from the background.
@MainActor
final class KeepAliveAudio {
    /// An interruption (a call, Siri) began. The mic is gone until it ends.
    var onInterruptionBegan: (() -> Void)?
    /// The session could not be brought back after an interruption.
    var onLost: ((String) -> Void)?

    private(set) var isRunning = false
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var observers: [NSObjectProtocol] = []
    private var preferBuiltInMic = true

    func start(preferBuiltInMic: Bool) throws {
        guard !isRunning else { return }
        self.preferBuiltInMic = preferBuiltInMic
        try configureSession()
        try startSilence()
        observe()
        isRunning = true
        Log.audio.info("keep-alive started (built-in mic preferred: \(preferBuiltInMic))")
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        stopSilence()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        Log.audio.info("keep-alive stopped")
    }

    /// Re-applies the input preference, e.g. after the setting changes.
    func setPreferBuiltInMic(_ prefer: Bool) {
        preferBuiltInMic = prefer
        guard isRunning else { return }
        try? configureSession()
    }

    // MARK: - Session

    private func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        // Mix with others so music and podcasts keep playing. HFP Bluetooth is
        // only allowed when the user wants their headset mic: enabling it moves
        // AirPods to the low-quality call profile for everything they play.
        var options: AVAudioSession.CategoryOptions = [.mixWithOthers, .defaultToSpeaker, .allowBluetoothA2DP]
        if !preferBuiltInMic { options.insert(.allowBluetoothHFP) }
        try session.setCategory(.playAndRecord, mode: .default, options: options)
        try session.setActive(true)
        applyPreferredInput()
    }

    private func applyPreferredInput() {
        let session = AVAudioSession.sharedInstance()
        if preferBuiltInMic {
            let builtIn = session.availableInputs?.first { $0.portType == .builtInMic }
            try? session.setPreferredInput(builtIn)
        } else {
            try? session.setPreferredInput(nil)
        }
    }

    // MARK: - Silence

    private func startSilence() throws {
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        engine.connect(player, to: engine.mainMixerNode, format: format)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100) else { return }
        buffer.frameLength = buffer.frameCapacity
        if let channels = buffer.floatChannelData {
            for channel in 0..<Int(format.channelCount) {
                channels[channel].update(repeating: 0, count: Int(buffer.frameLength))
            }
        }
        engine.prepare()
        try engine.start()
        player.scheduleBuffer(buffer, at: nil, options: .loops)
        player.play()
        self.engine = engine
        self.player = player

        observers.append(NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.restartSilence(reason: "configuration change") }
        })
    }

    private func stopSilence() {
        player?.stop()
        engine?.stop()
        player = nil
        engine = nil
    }

    private func restartSilence(reason: String) {
        guard isRunning else { return }
        Log.audio.info("keep-alive restarting: \(reason, privacy: .public)")
        stopSilence()
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            try startSilence()
        } catch {
            Log.audio.error("keep-alive restart failed: \(String(describing: error), privacy: .public)")
            onLost?("VoiceiQ lost the audio session")
        }
    }

    // MARK: - Interruptions

    private func observe() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            let info = note.userInfo ?? [:]
            let type = (info[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init(rawValue:))
            let options = AVAudioSession.InterruptionOptions(rawValue: info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
            Task { @MainActor in self?.handleInterruption(type, options: options) }
        })
        observers.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.applyPreferredInput() }
        })
        observers.append(center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isRunning else { return }
                do { try self.configureSession() } catch {}
                self.restartSilence(reason: "media services reset")
            }
        })
    }

    private func handleInterruption(_ type: AVAudioSession.InterruptionType?, options: AVAudioSession.InterruptionOptions) {
        guard isRunning, let type else { return }
        switch type {
        case .began:
            Log.audio.info("audio interruption began")
            onInterruptionBegan?()
        case .ended:
            Log.audio.info("audio interruption ended (resume: \(options.contains(.shouldResume)))")
            restartSilence(reason: "interruption ended")
        @unknown default:
            break
        }
    }
}
