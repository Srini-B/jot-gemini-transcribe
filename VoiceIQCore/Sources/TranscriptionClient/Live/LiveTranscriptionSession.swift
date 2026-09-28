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

/// The socket, behind a protocol so every failure mode in this file can be
/// exercised against a scripted fake with no network: setup timeout, mid-stream
/// drop, clean finish, server goAway, double-abort.
public protocol LiveTransport: AnyObject, Sendable {
    func connect() async throws
    func send(_ data: Data) async throws
    func receive() async throws -> Data
    func close()
}

/// How a live session ended. Only `.completed` may replace the real transcript,
/// and even then only after the caller has reconciled the byte count.
public enum LiveOutcome: Equatable, Sendable {
    /// Clean: setup completed, nothing dropped, activityEnd acknowledged, a final
    /// transcript arrived before the deadline.
    case completed(String)
    /// The server heard the whole recording and found no words in it. Not a
    /// live failure: the batch path reports the same silence, so this is not
    /// counted against live mode.
    case silent
    /// Anything else. The batch path over the CAF takes over; the words are on
    /// disk regardless. The string is for the log, never for the user.
    case unusable(String)
}

/// One live transcription session over one WebSocket.
///
/// The shape is dictated by two hard constraints:
///
/// 1. **The audio write queue must never wait for this.** `enqueue` is
///    `nonisolated`, takes no lock the socket holds, and cannot await. It appends
///    to a ring and signals; that is all.
///
/// 2. **`activityEnd` must never overtake the audio in front of it.** The server
///    finalizes on what it has received, so an end signal that jumps the queue
///    silently truncates the user's last words — precisely the tail that
///    `awaitTailBuffer` exists to rescue. Control items therefore travel *in
///    band*, through the same channel as the audio wakeups, and the send loop
///    drains the ring completely before it acts on one.
public actor LiveTranscriptionSession {

    private enum Command: Sendable {
        case pcmAvailable
        case endActivity
    }

    private let transport: LiveTransport
    private let dialect: LiveDialect
    public let ring: PCMRing

    private let commands: AsyncStream<Command>
    private let commandSink: AsyncStream<Command>.Continuation

    private var sendLoop: Task<Void, Never>?
    private var receiveLoop: Task<Void, Never>?

    private var finals: [String] = []
    private var latestPartial: String = ""
    /// `ring.acceptedBytes` when the server last said anything about the audio.
    /// The gap between this and the bytes sent since is how far the transcript
    /// lags the recording; past `stallSeconds` the stream is not trustworthy.
    private var acceptedAtLastTranscript: Int64 = 0
    private var bytesSinceActivityStart = 0
    /// Turns closed so far. `finish` waits until every closed turn has a final,
    /// not just until some final exists, because rolled turns leave earlier
    /// finals in place while the last one is still on its way.
    private var turnsEnded = 0
    /// Turns the server has finished transcribing (`generationComplete`).
    private var turnsCompleted = 0
    /// The socket reports usage per turn; a later frame supersedes an earlier
    /// one for the same turn, so the largest total wins rather than the sum.
    private var reportedUsage: TokenUsage?
    private var failure: String?
    private var didSetup = false
    private var activityEndFlushed = false
    private var closed = false

    /// Partials for the HUD. Separate from the outcome on purpose — nothing that
    /// arrives here is allowed to become the transcript.
    public nonisolated let partials: AsyncStream<String>
    private let partialSink: AsyncStream<String>.Continuation

    /// A Gemini Live session.
    public init(transport: LiveTransport, setup: LiveSetup, ring: PCMRing = PCMRing()) {
        self.init(transport: transport, dialect: GeminiLiveDialect(setup: setup), ring: ring)
    }

    public init(transport: LiveTransport, dialect: LiveDialect, ring: PCMRing = PCMRing()) {
        self.transport = transport
        self.dialect = dialect
        self.ring = ring
        // Control items must never be dropped, so this stream is unbounded — it
        // carries at most a handful of wakeups, not audio. The audio is in the
        // ring, which is the only thing with a drop policy.
        (self.commands, self.commandSink) = AsyncStream<Command>.makeStream(bufferingPolicy: .unbounded)
        (self.partials, self.partialSink) = AsyncStream<String>.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    /// Called from the audio write queue. Must not block, must not await.
    public nonisolated func enqueue(_ pcm: Data) {
        ring.append(pcm)
        commandSink.yield(.pcmAvailable)
    }

    /// Connects, handshakes, and opens the pumps. Throws if the socket or the
    /// credential is refused — the caller falls back to the batch path.
    public func start(setupTimeout: TimeInterval = 5.0) async throws {
        try await transport.connect()
        try await transport.send(dialect.setupFrame())

        // Wait for setupComplete before streaming. Audio arriving meanwhile is
        // already accumulating in the ring, so nothing is lost by waiting.
        //
        // Every receive is raced against the clock. Checking the deadline only
        // between receives would not bound anything: a socket that connects and
        // then says nothing — a proxy holding the upgrade, a server that accepted
        // the TCP connection and stalled — parks here for the transport's own
        // 30s timeout, and dictation cannot fall back to the batch path until
        // this returns. The bound has to be on the wait itself.
        let deadline = Date().addingTimeInterval(setupTimeout)
        while Date() < deadline {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { break }
            let frame = try await Self.receive(from: transport, within: remaining)
            guard let event = dialect.decode(frame).first else { continue }
            switch event {
            case .setupComplete:
                didSetup = true
            case .failed(let why):
                throw LiveError.refused(why)
            default:
                continue
            }
            break
        }
        guard didSetup else { throw LiveError.setupTimedOut }

        if let start = dialect.activityStartFrame() { try await transport.send(start) }
        startPumps()
    }

    /// Races a receive against a deadline. Returns the frame, or throws
    /// `LiveError.setupTimedOut` — either way it returns *promptly*, which is the
    /// whole point: the caller's fallback cannot start until this does.
    private static func receive(from transport: LiveTransport, within seconds: TimeInterval) async throws -> Data {
        try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask { try await transport.receive() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
                throw LiveError.setupTimedOut
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw LiveError.setupTimedOut }
            return first
        }
    }

    private func startPumps() {
        receiveLoop = Task { [weak self] in await self?.runReceiveLoop() }
        sendLoop = Task { [weak self] in await self?.runSendLoop() }
    }

    private func runSendLoop() async {
        for await command in commands {
            if closed { return }
            let isEnding = (command == .endActivity)
            // Coalesce into >=100ms (3,200-byte) frames during normal streaming,
            // and flush every remaining byte before activityEnd so activityEnd
            // never overtakes the audio in front of it.
            for chunk in ring.drainCoalesced(flushAll: isEnding) {
                do {
                    try await transport.send(dialect.audioFrame(chunk))
                    ring.markAccepted(chunk.count)
                    bytesSinceActivityStart += chunk.count
                    if !isEnding, Self.shouldRollActivity(bytesSinceStart: bytesSinceActivityStart, chunk: chunk) {
                        // Chunks already drained from the ring keep flowing
                        // into the new turn; nothing is dropped.
                        try await rollActivity()
                    }
                } catch {
                    recordFailure("send failed: \(error)")
                    return
                }
            }
            if isEnding {
                // A turn with no audio yet (a roll just before the key came up)
                // has nothing to end; OpenAI answers an empty commit with an
                // error, and Gemini would never send its final.
                guard bytesSinceActivityStart > 0 || turnsEnded == 0 else {
                    activityEndFlushed = true
                    return
                }
                do {
                    try await transport.send(dialect.activityEndFrame())
                    turnsEnded += 1
                } catch {
                    recordFailure("activityEnd failed: \(error)")
                }
                activityEndFlushed = true
                return
            }
        }
    }

    /// Closes the current turn and opens the next one.
    ///
    /// MEASURED 2026-09-27: sending `activityStart` in the same breath as
    /// `activityEnd` made the server drop the turn it was closing — no final,
    /// and the next turn's partials stopped too. It needs to finish the old
    /// turn (`generationComplete`, about a second after `activityEnd`) before
    /// a new one opens. Audio keeps landing in the ring during the wait, so
    /// nothing is lost; it goes out as soon as the new turn is open.
    private func rollActivity() async throws {
        try await transport.send(dialect.activityEndFrame())
        turnsEnded += 1
        let seconds = bytesSinceActivityStart / PCMRing.bytesPerSecond
        let deadline = Date().addingTimeInterval(Self.turnCloseWaitSeconds)
        while turnsCompleted < turnsEnded, failure == nil, Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        Log.transcription.debug("live: rolled activity \(self.turnsEnded) after \(seconds)s, completed=\(self.turnsCompleted >= self.turnsEnded)")
        if let start = dialect.activityStartFrame() { try await transport.send(start) }
        bytesSinceActivityStart = 0
    }

    private func runReceiveLoop() async {
        while !closed {
            do {
                let frame = try await transport.receive()
                if let usage = dialect.reportedUsage(in: frame) { noteUsage(usage) }
                if dialect.isGenerationComplete(frame) { turnsCompleted += 1 }
                let events = dialect.decode(frame)
                Log.transcription.debug("live frame: \(Self.describe(events, frame: frame), privacy: .public)")
                for event in events {
                    switch event {
                    case .partial(let text):
                        latestPartial = text
                        acceptedAtLastTranscript = ring.acceptedBytes
                        partialSink.yield(text)
                    case .partialDelta(let text):
                        latestPartial += text
                        acceptedAtLastTranscript = ring.acceptedBytes
                        partialSink.yield(latestPartial.trimmingCharacters(in: .whitespaces))
                    case .final(let text):
                        finals.append(text)
                        latestPartial = ""
                        acceptedAtLastTranscript = ring.acceptedBytes
                    case .goAway:
                        recordFailure("server sent goAway")
                        return
                    case .failed(let why):
                        recordFailure(why)
                        return
                    case .setupComplete:
                        continue
                    }
                }
            } catch {
                if !closed { recordFailure("receive failed: \(error)") }
                return
            }
        }
    }

    /// Event kinds and sizes for the debug log; the raw keys when nothing decoded.
    private static func describe(_ events: [LiveEvent], frame: Data) -> String {
        guard !events.isEmpty else {
            let root = (try? JSONSerialization.jsonObject(with: frame)) as? [String: Any]
            let inner = (root?["serverContent"] as? [String: Any])?.keys.sorted().joined(separator: ",") ?? ""
            return "undecoded keys=\(root?.keys.sorted().joined(separator: ",") ?? "?") serverContent=\(inner)"
        }
        return events.map {
            switch $0 {
            case .partial(let t): return "partial(\(t.count))"
            case .partialDelta(let t): return "delta(\(t.count))"
            case .final(let t): return "final(\(t.count))"
            case .goAway: return "goAway"
            case .failed(let w): return "failed(\(w))"
            case .setupComplete: return "setupComplete"
            }
        }.joined(separator: "+")
    }

    private func recordFailure(_ why: String) {
        if failure == nil { failure = why }
    }

    // MARK: - Activity rollover

    /// One activity is one server-side turn, and the server stops transcribing a
    /// turn that runs long: measured 2026-09-27, a seven-minute dictation held in
    /// a single activity produced partials for about four minutes and a final
    /// covering only the first half of the words, with the socket still healthy.
    /// Closing the turn every minute or so keeps every minute inside the range
    /// the server actually transcribes. The cut lands on a quiet frame when one
    /// comes along, so a word is rarely split; a talker who never pauses is cut
    /// anyway at the hard limit, and the cleanup pass hears the audio to mend it.
    static let activityRollSeconds = 60
    static let activityHardLimitSeconds = 90
    /// How long a roll waits for the server to finish the closed turn before
    /// opening the next. Measured at about one second; the cap keeps a stalled
    /// server from holding up audio.
    static let turnCloseWaitSeconds: TimeInterval = 2.5
    /// Below this RMS (int16 scale) a 100 ms frame is treated as a pause.
    static let quietFrameRMS = 400.0

    static func shouldRollActivity(bytesSinceStart: Int, chunk: Data) -> Bool {
        let seconds = bytesSinceStart / PCMRing.bytesPerSecond
        if seconds >= activityHardLimitSeconds { return true }
        guard seconds >= activityRollSeconds else { return false }
        return rms(chunk) < quietFrameRMS
    }

    static func rms(_ pcm: Data) -> Double {
        let count = pcm.count / 2
        guard count > 0 else { return 0 }
        let sum = pcm.withUnsafeBytes { raw -> Double in
            var acc = 0.0
            for i in 0..<count {
                let v = Double(raw.loadUnaligned(fromByteOffset: i * 2, as: Int16.self))
                acc += v * v
            }
            return acc
        }
        return (sum / Double(count)).squareRoot()
    }

    /// Audio the server accepted after its last word. A stream whose transcript
    /// stopped this far before the recording did is missing speech, whatever
    /// the byte reconciliation says, so the upload path takes over.
    static let stallSeconds = 120

    private var transcriptStalledSeconds: Int? {
        let lag = Int(ring.acceptedBytes - acceptedAtLastTranscript) / PCMRing.bytesPerSecond
        return lag >= Self.stallSeconds ? lag : nil
    }

    private func noteUsage(_ usage: TokenUsage) {
        if let current = reportedUsage, current.totalIn + current.totalOut >= usage.totalIn + usage.totalOut { return }
        reportedUsage = usage
    }

    /// Books this session against the caller's `UsageMeter.scope`. Estimates
    /// from bytes sent and text received when the server sent no counts.
    private func recordUsage(outputText: String) {
        let usage = dialect.usage(reported: reportedUsage,
                                  audioSeconds: Double(ring.acceptedBytes) / 32_000,
                                  outputCharacters: outputText.count)
        UsageMeter.record(stage: .liveTranscribe, model: dialect.model, usage: usage)
    }

    /// Ends the turn and waits for the server's last word.
    ///
    /// Called only after `AudioCaptureEngine.stop()` has returned, because audio
    /// keeps arriving through the tail drain and the trailing-capture window —
    /// key-up is not the end of speech.
    public func finish(deadline: TimeInterval = 6.0) async -> LiveOutcome {
        guard didSetup else { return .unusable("setup never completed") }
        if let failure { close(); return .unusable(failure) }

        commandSink.yield(.endActivity)
        commandSink.finish()

        // Wait for the send loop to actually flush activityEnd before starting
        // the clock on the final transcript.
        let flushDeadline = Date().addingTimeInterval(2.0)
        while !activityEndFlushed, failure == nil, Date() < flushDeadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        if let failure { close(); return .unusable(failure) }
        guard activityEndFlushed else { close(); return .unusable("activityEnd never flushed") }

        // A final may already have arrived. Otherwise wait, briefly.
        let finalDeadline = Date().addingTimeInterval(deadline)
        while finals.count < turnsEnded, failure == nil, Date() < finalDeadline {
            try? await Task.sleep(nanoseconds: 30_000_000)
        }
        close()
        recordUsage(outputText: finals.joined(separator: " "))

        if let failure { return .unusable(failure) }
        guard !finals.isEmpty else { return .unusable("no final transcript before deadline") }
        if ring.didDrop { return .unusable("dropped \(ring.droppedChunks) chunks — stream is truncated") }
        if let lag = transcriptStalledSeconds {
            return .unusable("transcript stalled \(lag)s before the recording ended — stream is truncated")
        }

        let joined = finals.filter { !$0.isEmpty }.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        Log.transcription.info("live finish: \(self.finals.count) finals for \(self.turnsEnded) turns, \(joined.count) chars over \(Int(self.ring.acceptedBytes) / PCMRing.bytesPerSecond)s")
        guard !joined.isEmpty else { return .silent }
        return .completed(joined)
    }

    /// Tear down without waiting. Idempotent — every path that abandons a session
    /// calls this, including several that run before `start` ever completed.
    public func abort() {
        close()
    }

    private func close() {
        guard !closed else { return }
        closed = true
        sendLoop?.cancel()
        receiveLoop?.cancel()
        commandSink.finish()
        partialSink.finish()
        transport.close()
    }

    /// Bytes the socket accepted, for reconciliation against `framesWritten * 2`.
    public var acceptedBytes: Int64 { ring.acceptedBytes }
}

public enum LiveError: Error, Equatable {
    case refused(String)
    case setupTimedOut
}
