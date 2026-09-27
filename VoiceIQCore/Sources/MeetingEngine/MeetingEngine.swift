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

import Combine
import Foundation

@MainActor public final class MeetingEngine: ObservableObject {
    @Published public private(set) var phase: MeetingPhase = .idle
    public var onNotice: ((String) -> Void)?
    /// The notes for a stopped recording are saved. The caller shows the same
    /// success mark a finished dictation gets.
    public var onNotesReady: (() -> Void)?
    /// A call was noticed while idle. The caller decides whether to record; nothing starts on its own.
    public var onCallDetected: ((CallSource) -> Void)?
    /// The noticed call went away before anyone accepted it.
    public var onCallEnded: (() -> Void)?
    public var autoDetect: Bool = false { didSet { autoDetect ? detector.start() : detector.stop() } }

    public let store: MeetingStore
    private let client: GeminiClient
    private let config: () -> GeminiConfig
    private let transcribeModel: String?
    private let summaryModel: String
    private lazy var detector = CallDetector()
    private var mic: MicTap?, system: SystemAudioTap?
    private var currentFolder: URL?, currentMeta: MeetingMeta?
    /// The call the detector currently sees, whether or not it was accepted.
    public private(set) var detectedSource: CallSource?

    public init(client: GeminiClient, store: MeetingStore = MeetingStore(), config: @escaping () -> GeminiConfig,
                transcribeModel: String? = nil, summaryModel: String = "gemini-3.8-flash") {
        self.client = client; self.store = store; self.config = config
        self.transcribeModel = transcribeModel; self.summaryModel = summaryModel
        detector.onChange = { [weak self] source in self?.detected(source) }
        failInterruptedRecordings()
    }

    /// A meeting still marked `.recording` at launch belonged to a process that
    /// died; nothing will ever stop it, so the list would show "Recording"
    /// forever.
    private func failInterruptedRecordings() {
        for var meta in store.list() where meta.status == .recording {
            meta.status = .failed("interrupted")
            meta.endedAt = meta.endedAt ?? meta.startedAt.addingTimeInterval(meta.durationSeconds)
            try? store.save(meta: meta)
        }
    }

    public var isRecording: Bool { if case .recording = phase { return true }; return false }

    /// Option-M: start when nothing is recording, stop when something is.
    public func toggleRecording() {
        switch phase {
        case .recording: stopRecording()
        case .idle, .callDetected, .failed: startRecording(source: detectedSource)
        case .processing: onNotice?("Meeting notes are still being made")
        }
    }

    /// The pill's Accept button.
    public func acceptDetectedCall() {
        guard case let .callDetected(source) = phase else { return }
        startRecording(source: source)
    }

    /// The pill's dismiss. The same call is not offered again; the next one is.
    public func dismissDetectedCall() {
        guard case .callDetected = phase else { return }
        phase = .idle
    }

    public func startRecording(source: CallSource? = nil) {
        switch phase { case .idle, .callDetected, .failed: break; default: return }
        let id = MeetingID(), now = Date(), meta = MeetingMeta(id: id, startedAt: now, source: source)
        do {
            let folder = try store.create(meta: meta)
            let mic = MicTap(url: folder.appendingPathComponent("mic.caf"))
            let system = SystemAudioTap(url: folder.appendingPathComponent("system.caf"))
            // Mic first. MEASURED 2026-09-26 (macOS 26.5, built-in mic): with the
            // tap's aggregate device already running, `AudioDeviceStart` on the
            // mic blocked the main thread for 9 s to forever while coreaudiod
            // retried "StartIOThread ... Error: 0x3C" every 14 s (4 of 7 runs).
            // Mic-then-tap started in 40 ms in every run and the tap still
            // delivered system audio.
            try mic.start()
            do { try system.start() } catch { _ = mic.stop(); throw error }
            self.mic = mic; self.system = system
            currentFolder = folder; currentMeta = meta
            phase = .recording(id, since: now)
        } catch { fail(id, error) }
    }

    public func stopRecording() {
        guard case let .recording(id, _) = phase, let folder = currentFolder, var meta = currentMeta else { return }
        let micDuration = mic?.stop() ?? 0, systemDuration = system?.stop() ?? 0
        mic = nil; system = nil; phase = .processing(id)
        meta.endedAt = Date(); meta.durationSeconds = max(micDuration, systemDuration); meta.status = .transcribing
        currentMeta = meta; try? store.save(meta: meta)
        Task { await UsageMeter.$scope.withValue(UsageScope(activity: .meeting, sessionID: id.uuid.uuidString)) {
            await process(id: id, folder: folder, meta: meta, remix: true)
        } }
    }

    public func retry(id: MeetingID) {
        guard let folder = store.folder(for: id), let meta = store.list().first(where: { $0.id == id }) else { return }
        phase = .processing(id)
        Task { await UsageMeter.$scope.withValue(UsageScope(activity: .meeting, sessionID: id.uuid.uuidString)) {
            await process(id: id, folder: folder, meta: meta, remix: false)
        } }
    }

    private func process(id: MeetingID, folder: URL, meta original: MeetingMeta, remix: Bool) async {
        var meta = original
        do {
            let mixed = folder.appendingPathComponent("mixed.caf")
            if remix { meta.durationSeconds = try AudioMixer.mixToMono(micURL: folder.appendingPathComponent("mic.caf"), systemURL: folder.appendingPathComponent("system.caf"), outputURL: mixed) }
            let cfg = config(), model = transcribeModel ?? cfg.transcribeModel
            let stats = try AudioMixer.speechStats(url: mixed)
            guard stats.hasSpeech else {
                Log.meeting.info("no speech in recording (\(String(format: "%.1f", stats.activeSeconds), privacy: .public)s active, \(String(format: "%.1f", stats.spreadDB), privacy: .public) dB spread) — skipping transcription")
                try finish(id: id, meta: &meta, transcript: [], notes: Self.emptyNotes(reason: "No speech was recorded."))
                return
            }
            meta.status = .transcribing; try store.save(meta: meta)
            let transcript = try await MeetingTranscriber(client: client).transcribe(cafURL: mixed, model: model, endpoint: cfg.endpoint, deadline: 1800)
            let words = transcript.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count }
            guard words >= Self.minimumSummarizableWords else {
                Log.meeting.info("transcript too short to summarize (\(words, privacy: .public) words)")
                try finish(id: id, meta: &meta, transcript: transcript, notes: Self.emptyNotes(reason: "Not enough speech to summarize."))
                return
            }
            try store.save(transcript: transcript, id: id)
            meta.status = .summarizing; try store.save(meta: meta)
            let text = transcript.map { "\($0.speaker): \($0.text)" }.joined(separator: "\n")
            let notes = try await client.summarizeMeeting(transcript: text, model: summaryModel, endpoint: cfg.endpoint, deadline: 300)
            try finish(id: id, meta: &meta, transcript: transcript, notes: notes)
        } catch { meta.status = .failed(String(describing: error)); try? store.save(meta: meta); fail(id, error) }
    }

    /// Fewer words than this and the notes model has nothing to work with; it
    /// would write a summary saying so, in whatever language the fragment is.
    static let minimumSummarizableWords = 8

    static func emptyNotes(reason: String) -> MeetingNotes {
        MeetingNotes(title: "No speech recorded", summary: reason, decisions: [], actions: [], notes: [])
    }

    private func finish(id: MeetingID, meta: inout MeetingMeta, transcript: [TranscriptSegment], notes: MeetingNotes) throws {
        try store.save(transcript: transcript, id: id)
        try store.save(notes: notes, id: id)
        meta.title = notes.title; meta.status = .done; try store.save(meta: meta)
        phase = .idle; currentFolder = nil; currentMeta = nil; onNotesReady?()
    }

    /// Detection only ever offers. A recording in progress is never stopped by
    /// the detector losing sight of the call (muting in Meet drops the mic
    /// capture it watches), and nothing starts until someone accepts.
    private func detected(_ source: CallSource?) {
        detectedSource = source
        if let source {
            guard case .idle = phase else { return }
            phase = .callDetected(source)
            onCallDetected?(source)
        } else if case .callDetected = phase {
            phase = .idle
            onCallEnded?()
        }
    }
    private func fail(_ id: MeetingID, _ error: Error) { phase = .failed(id, String(describing: error)); onNotice?("Meeting recording failed") }
    public static func name(_ source: CallSource) -> String { switch source { case let .app(_, name): return name; case let .browser(_, host): return host } }
}
