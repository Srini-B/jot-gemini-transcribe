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
    /// Routes to try in order; see `ModelRoute.meetingOrder`.
    private let providers: @Sendable () -> [ModelRoute]
    private lazy var detector = CallDetector()
    private var mic: MicTap?, system: SystemAudioTap?
    private var currentFolder: URL?, currentMeta: MeetingMeta?
    /// The call the detector currently sees, whether or not it was accepted.
    public private(set) var detectedSource: CallSource?

    public init(client: GeminiClient, store: MeetingStore = MeetingStore(), config: @escaping () -> GeminiConfig,
                transcribeModel: String? = nil, summaryModel: String = "gemini-3.8-flash",
                providers: @escaping @Sendable () -> [ModelRoute] = { [ModelRoute(provider: .gemini, gateway: .direct)] }) {
        self.client = client; self.store = store; self.config = config
        self.transcribeModel = transcribeModel; self.summaryModel = summaryModel; self.providers = providers
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
            await process(id: id, folder: folder, meta: meta)
        } }
    }

    /// Transcribes again from the audio (finished windows are reused) and writes new notes.
    public func retry(id: MeetingID) {
        switch phase { case .idle, .failed, .callDetected: break; default: return }
        guard let folder = store.folder(for: id), let meta = store.list().first(where: { $0.id == id }) else { return }
        phase = .processing(id)
        Task { await UsageMeter.$scope.withValue(UsageScope(activity: .meeting, sessionID: id.uuid.uuidString)) {
            await process(id: id, folder: folder, meta: meta)
        } }
    }

    /// New notes from the saved transcript, using the speaker names typed since.
    public func regenerateNotes(id: MeetingID) {
        switch phase { case .idle, .failed, .callDetected: break; default: return }
        guard var meta = store.list().first(where: { $0.id == id }),
              let transcript = try? store.loadTranscript(id: id), !transcript.isEmpty else { return }
        phase = .processing(id)
        Task { await UsageMeter.$scope.withValue(UsageScope(activity: .meeting, sessionID: id.uuid.uuidString)) {
            do {
                meta.status = .summarizing; try store.save(meta: meta)
                guard !providers().isEmpty else { throw MeetingFailure.noRoute }
                let notes = try await writeNotes(transcript: transcript, meta: meta)
                try finish(id: id, meta: &meta, transcript: transcript, notes: notes)
            } catch { saveFailure(id: id, meta: &meta, error: error) }
        } }
    }

    private func process(id: MeetingID, folder: URL, meta original: MeetingMeta) async {
        var meta = original
        do {
            let cfg = config()
            let mic = try AudioMixer.speechStats(url: folder.appendingPathComponent("mic.caf"))
            let system = try AudioMixer.speechStats(url: folder.appendingPathComponent("system.caf"))
            guard mic.hasSpeech || system.hasSpeech else {
                Log.meeting.info("no speech in recording (mic \(String(format: "%.1f", mic.activeSeconds), privacy: .public)s, system \(String(format: "%.1f", system.activeSeconds), privacy: .public)s active) — skipping transcription")
                try finish(id: id, meta: &meta, transcript: [], notes: Self.emptyNotes(reason: "No speech was recorded."))
                return
            }
            guard !providers().isEmpty else { throw MeetingFailure.noRoute }
            meta.status = .transcribing; try store.save(meta: meta)
            let transcriber = MeetingTranscriber(client: client,
                                                 models: .init(transcribe: transcribeModel ?? cfg.transcribeModel, flash: summaryModel),
                                                 endpoint: cfg.endpoint, providers: providers)
            let transcript = try await transcriber.transcribe(folder: folder)
            let words = transcript.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count }
            guard words >= Self.minimumSummarizableWords else {
                Log.meeting.info("transcript too short to summarize (\(words, privacy: .public) words)")
                try finish(id: id, meta: &meta, transcript: transcript, notes: Self.emptyNotes(reason: "Not enough speech to summarize."))
                return
            }
            try store.save(transcript: transcript, id: id)
            meta.status = .summarizing; try store.save(meta: meta)
            let notes = try await writeNotes(transcript: transcript, meta: meta)
            try finish(id: id, meta: &meta, transcript: transcript, notes: notes)
        } catch { saveFailure(id: id, meta: &meta, error: error) }
    }

    /// The recording stays; the meeting is marked failed with a reason the
    /// Meetings list shows, and Retry runs it again with the keys stored then.
    private func saveFailure(id: MeetingID, meta: inout MeetingMeta, error: Error) {
        let reason = MeetingFailure.reason(for: error, routes: providers())
        Log.meeting.error("meeting \(id.uuid.uuidString, privacy: .public) failed: \(String(describing: error), privacy: .public)")
        meta.status = .failed(reason); try? store.save(meta: meta)
        phase = .failed(id, reason); currentFolder = nil; currentMeta = nil
        onNotice?(error as? MeetingFailure == .noRoute ? "Meeting saved without a transcript — add a key, then Retry in Meetings"
                                                       : "Meeting transcript failed — see Meetings")
    }

    private func writeNotes(transcript: [TranscriptSegment], meta: MeetingMeta) async throws -> MeetingNotes {
        let cfg = config()
        let prompt = MeetingNotesPrompt.build(transcript: transcript, context: .init(
            startedAt: meta.startedAt, durationSeconds: meta.durationSeconds,
            app: meta.source.map(Self.name), names: meta.speakerNames))
        var lastError: Error = TranscriptionError.network("no_provider")
        for via in providers() {
            do {
                let text = try await client.meetingNotesJSON(prompt: prompt, model: summaryModel, endpoint: cfg.endpoint,
                                                             deadline: 300, via: via)
                return try MeetingNotesPrompt.parse(text)
            } catch {
                Log.meeting.error("notes via \(via.label, privacy: .public) failed: \(String(describing: error), privacy: .public)")
                lastError = error
            }
        }
        throw lastError
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

/// Why a meeting has no transcript or notes, in words the Meetings list can
/// show. The raw error goes to the log.
public enum MeetingFailure: Error, Equatable {
    /// No stored key reaches a model that can transcribe a meeting.
    case noRoute

    static let fixHint = "The recording is saved. Press Retry after fixing this."

    static func reason(for error: Error, routes: [ModelRoute]) -> String {
        let tried = routes.map(\.displayName).joined(separator: ", ")
        switch error {
        case MeetingFailure.noRoute:
            return "No key can transcribe meetings. Add a Gemini, OpenAI, OpenRouter or Vercel AI Gateway key in Settings → Advanced. The recording is saved; press Retry once a key is added."
        case let error as TranscriptionError:
            switch error {
            case .auth:
                return "The API key was rejected (\(tried)). Check it in Settings → Advanced. \(fixHint)"
            case .rateLimitedDaily:
                return "The daily quota is used up (\(tried)). \(fixHint)"
            case .rateLimitedTransient:
                return "Rate limited for too long (\(tried)). Try again in a few minutes. \(fixHint)"
            case .network("gateway_insufficient_credits"):
                return "The gateway account is out of credit (\(tried)). \(fixHint)"
            case .modelUnavailable(let model, _):
                return "Your key can't use \(model) (\(tried)). \(fixHint)"
            case .offline:
                return "You were offline when the meeting was transcribed. \(fixHint)"
            case .timeout, .network:
                return "Couldn't reach \(tried.isEmpty ? "the provider" : tried). \(fixHint)"
            case .safetyBlocked:
                return "The provider declined to transcribe this meeting (\(tried)). \(fixHint)"
            case .badRequest, .emptyTranscript:
                return "Transcription failed (\(tried)). \(fixHint)"
            }
        default:
            return "Transcription failed: \(error.localizedDescription). \(fixHint)"
        }
    }
}
