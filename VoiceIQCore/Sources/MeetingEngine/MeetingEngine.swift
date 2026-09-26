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
    /// Live preview text while recording; empty otherwise. Display only.
    @Published public private(set) var livePreview: String = ""
    public var onNotice: ((String) -> Void)?
    /// A call was noticed while idle. The caller decides whether to record; nothing starts on its own.
    public var onCallDetected: ((CallSource) -> Void)?
    /// The noticed call went away before anyone accepted it.
    public var onCallEnded: (() -> Void)?
    public var autoDetect: Bool = false { didSet { autoDetect ? detector.start() : detector.stop() } }
    /// Builds the live socket for the on-pill preview; nil turns the preview off.
    public var makeLiveSession: MeetingLivePreview.SessionFactory?

    public let store: MeetingStore
    private let client: GeminiClient
    private let config: () -> GeminiConfig
    private let transcribeModel: String?
    private let summaryModel: String
    private lazy var detector = CallDetector()
    private var mic: MicTap?, system: SystemAudioTap?
    private var preview: MeetingLivePreview?
    private var currentFolder: URL?, currentMeta: MeetingMeta?
    /// The call the detector currently sees, whether or not it was accepted.
    public private(set) var detectedSource: CallSource?

    public init(client: GeminiClient, store: MeetingStore = MeetingStore(), config: @escaping () -> GeminiConfig,
                transcribeModel: String? = nil, summaryModel: String = "gemini-3.8-flash") {
        self.client = client; self.store = store; self.config = config
        self.transcribeModel = transcribeModel; self.summaryModel = summaryModel
        detector.onChange = { [weak self] source in self?.detected(source) }
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
            let preview = makeLiveSession.map { MeetingLivePreview(makeSession: $0) }
            if let preview {
                preview.onText = { [weak self] text in Task { @MainActor in self?.livePreview = text } }
                mic.pcmSink = { [weak preview] pcm in preview?.pushMic(pcm) }
                system.pcmSink = { [weak preview] pcm in preview?.pushSystem(pcm) }
            }
            // System tap first so its aggregate device exists before the mic IOProc starts.
            try system.start()
            do { try mic.start() } catch { _ = system.stop(); throw error }
            self.mic = mic; self.system = system; self.preview = preview
            currentFolder = folder; currentMeta = meta; livePreview = ""
            preview?.start()
            phase = .recording(id, since: now)
        } catch { fail(id, error) }
    }

    public func stopRecording() {
        guard case let .recording(id, _) = phase, let folder = currentFolder, var meta = currentMeta else { return }
        let micDuration = mic?.stop() ?? 0, systemDuration = system?.stop() ?? 0
        mic = nil; system = nil; phase = .processing(id)
        if let preview { self.preview = nil; Task { await preview.stop() } }
        livePreview = ""
        meta.endedAt = Date(); meta.durationSeconds = max(micDuration, systemDuration); meta.status = .transcribing
        currentMeta = meta; try? store.save(meta: meta)
        Task { await process(id: id, folder: folder, meta: meta, remix: true) }
    }

    public func retry(id: MeetingID) {
        guard let folder = store.folder(for: id), let meta = store.list().first(where: { $0.id == id }) else { return }
        phase = .processing(id); Task { await process(id: id, folder: folder, meta: meta, remix: false) }
    }

    private func process(id: MeetingID, folder: URL, meta original: MeetingMeta, remix: Bool) async {
        var meta = original
        do {
            let mixed = folder.appendingPathComponent("mixed.caf")
            if remix { meta.durationSeconds = try AudioMixer.mixToMono(micURL: folder.appendingPathComponent("mic.caf"), systemURL: folder.appendingPathComponent("system.caf"), outputURL: mixed) }
            let cfg = config(), model = transcribeModel ?? cfg.transcribeModel
            meta.status = .transcribing; try store.save(meta: meta)
            let transcript = try await MeetingTranscriber(client: client).transcribe(cafURL: mixed, model: model, endpoint: cfg.endpoint, deadline: 1800)
            try store.save(transcript: transcript, id: id)
            meta.status = .summarizing; try store.save(meta: meta)
            let text = transcript.map { "\($0.speaker): \($0.text)" }.joined(separator: "\n")
            let notes = try await client.summarizeMeeting(transcript: text, model: summaryModel, endpoint: cfg.endpoint, deadline: 300)
            try store.save(notes: notes, id: id)
            meta.title = notes.title; meta.status = .done; try store.save(meta: meta)
            phase = .idle; currentFolder = nil; currentMeta = nil; onNotice?("Meeting notes ready")
        } catch { meta.status = .failed(String(describing: error)); try? store.save(meta: meta); fail(id, error) }
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
