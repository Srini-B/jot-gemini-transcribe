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

/// Live transcript shown on the pill while a meeting records. Display only:
/// the saved transcript still comes from the CAF files after the meeting ends.
///
/// The Live API caps a session at ten minutes, so sessions rotate every nine:
/// the finished session's final text is kept as a tail and the next session
/// continues from there. A session that fails or refuses to open is retried on
/// the next rotation; the recording itself never depends on this.
public final class MeetingLivePreview: @unchecked Sendable {
    public typealias SessionFactory = @Sendable () -> LiveTranscriptionSession?

    /// The text to show. Called off the main thread; each value replaces the last.
    public var onText: (@Sendable (String) -> Void)?

    static let sessionSeconds: TimeInterval = 540
    static let retrySeconds: TimeInterval = 30
    static let tailCharacters = 600

    private let makeSession: SessionFactory
    private let mixer = LaneMixer()
    private let lock = NSLock()
    private var session: LiveTranscriptionSession?
    private var running = false
    private var committed = ""
    private var rotation: Task<Void, Never>?
    private var partialPump: Task<Void, Never>?

    public init(makeSession: @escaping SessionFactory) {
        self.makeSession = makeSession
    }

    public func start() {
        lock.lock(); running = true; committed = ""; lock.unlock()
        openSession()
    }

    public func stop() async {
        let current = withLock { running = false; let s = session; session = nil; return s }
        rotation?.cancel(); rotation = nil
        partialPump?.cancel(); partialPump = nil
        if let current { await current.abort() }
        mixer.reset()
    }

    public func pushMic(_ pcm: Data) { mixer.push(mic: pcm) { forward($0) } }
    public func pushSystem(_ pcm: Data) { mixer.push(system: pcm) { forward($0) } }

    private func forward(_ pcm: Data) {
        lock.lock(); let current = session; lock.unlock()
        current?.enqueue(pcm)
    }

    private func openSession() {
        lock.lock()
        guard running else { lock.unlock(); return }
        guard let next = makeSession() else {
            lock.unlock()
            Log.meeting.info("live preview: no session available, retrying in \(Self.retrySeconds, privacy: .public)s")
            scheduleRotation(after: Self.retrySeconds)
            return
        }
        session = next
        lock.unlock()

        partialPump?.cancel()
        partialPump = Task { [weak self] in
            for await partial in next.partials {
                guard let self else { return }
                self.publish(partial: partial)
            }
        }
        Task { [weak self] in
            do { try await next.start() }
            catch {
                Log.meeting.info("live preview session did not open: \(String(describing: error), privacy: .public)")
                self?.dropIfCurrent(next)
            }
        }
        scheduleRotation(after: Self.sessionSeconds)
    }

    private func scheduleRotation(after seconds: TimeInterval) {
        rotation?.cancel()
        rotation = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.rotate()
        }
    }

    private func rotate() async {
        let ending = withLock { let s = session; session = nil; return s }
        partialPump?.cancel(); partialPump = nil
        if let ending {
            let outcome = await ending.finish(deadline: 3)
            if case let .completed(text) = outcome {
                withLock { committed = Self.tail(committed.isEmpty ? text : committed + " " + text) }
                publish(partial: "")
            } else if case let .unusable(why) = outcome {
                Log.meeting.info("live preview session ended: \(why, privacy: .public)")
            }
        }
        openSession()
    }

    private func dropIfCurrent(_ failed: LiveTranscriptionSession) {
        lock.lock()
        if session === failed { session = nil }
        lock.unlock()
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body()
    }

    private func publish(partial: String) {
        lock.lock(); let base = committed; lock.unlock()
        let joined = partial.isEmpty ? base : (base.isEmpty ? partial : base + " " + partial)
        onText?(Self.tail(joined))
    }

    private static func tail(_ text: String) -> String {
        text.count <= tailCharacters ? text : String(text.suffix(tailCharacters))
    }
}

/// Sums the mic and system lanes into one 16 kHz mono int16 stream, 100 ms at a
/// time. The two IOProcs run on different clocks, so a lane that leads by more
/// than a second while the other is empty is drained alone rather than held.
final class LaneMixer {
    private let lock = NSLock()
    private var mic = Data(), system = Data()
    private let frameBytes = 3_200
    private let maxLeadBytes = 32_000

    func push(mic data: Data, emit: (Data) -> Void) {
        lock.lock(); mic.append(data); let out = drain(); lock.unlock()
        out.forEach(emit)
    }

    func push(system data: Data, emit: (Data) -> Void) {
        lock.lock(); system.append(data); let out = drain(); lock.unlock()
        out.forEach(emit)
    }

    func reset() { lock.lock(); mic.removeAll(); system.removeAll(); lock.unlock() }

    private func drain() -> [Data] {
        var out: [Data] = []
        while mic.count >= frameBytes, system.count >= frameBytes {
            out.append(Self.sum(mic.prefix(frameBytes), system.prefix(frameBytes)))
            mic.removeFirst(frameBytes); system.removeFirst(frameBytes)
        }
        while mic.count >= frameBytes + maxLeadBytes, system.count < frameBytes {
            out.append(Data(mic.prefix(frameBytes))); mic.removeFirst(frameBytes)
        }
        while system.count >= frameBytes + maxLeadBytes, mic.count < frameBytes {
            out.append(Data(system.prefix(frameBytes))); system.removeFirst(frameBytes)
        }
        return out
    }

    private static func sum(_ a: Data, _ b: Data) -> Data {
        let count = min(a.count, b.count) / 2
        var out = [Int16](repeating: 0, count: count)
        a.withUnsafeBytes { ra in
            b.withUnsafeBytes { rb in
                let pa = ra.bindMemory(to: Int16.self), pb = rb.bindMemory(to: Int16.self)
                for i in 0..<count {
                    out[i] = Int16(clamping: Int32(pa[i]) + Int32(pb[i]))
                }
            }
        }
        return out.withUnsafeBufferPointer { Data(buffer: $0) }
    }
}
