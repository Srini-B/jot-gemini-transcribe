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
    public var autoDetect: Bool = false { didSet { autoDetect ? detector.start() : detector.stop() } }

    public let store: MeetingStore
    private let client: GeminiClient
    private let config: () -> GeminiConfig
    private let transcribeModel: String?
    private let summaryModel: String
    private lazy var detector = CallDetector()
    private var mic: MicTap?, system: SystemAudioTap?
    private var currentFolder: URL?, currentMeta: MeetingMeta?

    public init(client: GeminiClient, store: MeetingStore = MeetingStore(), config: @escaping () -> GeminiConfig,
                transcribeModel: String? = nil, summaryModel: String = "gemini-3.8-flash") {
        self.client = client; self.store = store; self.config = config
        self.transcribeModel = transcribeModel; self.summaryModel = summaryModel
        detector.onChange = { [weak self] source in self?.detected(source) }
    }

    public func startRecording(source: CallSource? = nil) {
        guard case .idle = phase else { return }
        let id = MeetingID(), now = Date(), meta = MeetingMeta(id: id, startedAt: now, source: source)
        do {
            let folder = try store.create(meta: meta)
            let mic = MicTap(url: folder.appendingPathComponent("mic.caf"))
            let system = SystemAudioTap(url: folder.appendingPathComponent("system.caf"))
            // System tap first so its aggregate device exists before the mic IOProc starts.
            try system.start()
            do { try mic.start() } catch { _ = system.stop(); throw error }
            self.mic = mic; self.system = system; currentFolder = folder; currentMeta = meta
            phase = .recording(id, since: now); onNotice?("Recording meeting\(source.map { " (\(Self.name($0)))" } ?? "")")
        } catch { fail(id, error) }
    }

    public func stopRecording() {
        guard case let .recording(id, _) = phase, let folder = currentFolder, var meta = currentMeta else { return }
        let micDuration = mic?.stop() ?? 0, systemDuration = system?.stop() ?? 0
        mic = nil; system = nil; phase = .processing(id)
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

    private func detected(_ source: CallSource?) {
        if let source, case .idle = phase { phase = .callDetected(source); phase = .idle; startRecording(source: source) }
        else if source == nil, case .recording = phase { stopRecording() }
    }
    private func fail(_ id: MeetingID, _ error: Error) { phase = .failed(id, String(describing: error)); onNotice?("Meeting recording failed") }
    private static func name(_ source: CallSource) -> String { switch source { case let .app(_, name): return name; case let .browser(_, host): return host } }
}
