import Foundation

/// Local, on-device counters for how often live transcription actually works.
///
/// Live mode cannot lose words — a bad session falls back to uploading the
/// recording. What that safety costs is *visibility*: every failure looks like a
/// slightly slower dictation, so a live path that is broken for a whole week is
/// indistinguishable from one that is merely sometimes slow. Nobody would notice,
/// and nobody could answer "is live mode good?" with a number.
///
/// This is that number. It stays on this Mac — `UserDefaults`, no network, no
/// identifiers, nothing that leaves the device. The repository's no-telemetry
/// rule is about not phoning home, not about refusing to count for the user's own
/// benefit, and the Settings footer that reads these counters is the whole point:
/// the person deciding whether to leave live mode on gets the evidence.
public struct LiveStats: Sendable {

    /// Why a dictation did not use its live transcript. Kept coarse on purpose:
    /// these are for a human reading one line of Settings, not an analytics
    /// schema, and a long tail of near-identical reasons would obscure the
    /// distinction that matters — network, or us.
    public enum Fallback: String, Sendable, CaseIterable {
        /// The socket never opened: offline, refused, or the handshake timed out.
        case neverOpened
        /// It opened, then died, or the server ended it.
        case droppedMidSession
        /// Audio was evicted from the ring, so the transcript would be truncated.
        case truncated
        /// The server never sent a final transcript in time.
        case noFinal
    }

    private static let attemptsKey = "liveAttempts"
    private static let successesKey = "liveSuccesses"
    private static let reasonPrefix = "liveFallback_"
    private static let consecutiveKey = "liveConsecutiveFailures"
    private static let lastFailureKey = "liveLastFailureAt"

    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func recordSuccess() {
        defaults.set(defaults.integer(forKey: Self.attemptsKey) + 1, forKey: Self.attemptsKey)
        defaults.set(defaults.integer(forKey: Self.successesKey) + 1, forKey: Self.successesKey)
        defaults.set(0, forKey: Self.consecutiveKey)
    }

    public func recordFallback(_ reason: Fallback, at now: Date = Date()) {
        defaults.set(defaults.integer(forKey: Self.attemptsKey) + 1, forKey: Self.attemptsKey)
        let key = Self.reasonPrefix + reason.rawValue
        defaults.set(defaults.integer(forKey: key) + 1, forKey: key)
        defaults.set(defaults.integer(forKey: Self.consecutiveKey) + 1, forKey: Self.consecutiveKey)
        defaults.set(now.timeIntervalSinceReferenceDate, forKey: Self.lastFailureKey)
    }

    public var attempts: Int { defaults.integer(forKey: Self.attemptsKey) }
    public var successes: Int { defaults.integer(forKey: Self.successesKey) }
    public var consecutiveFailures: Int { defaults.integer(forKey: Self.consecutiveKey) }

    public func count(of reason: Fallback) -> Int {
        defaults.integer(forKey: Self.reasonPrefix + reason.rawValue)
    }

    /// Stop opening sockets after this many failures in a row.
    ///
    /// Every failed attempt costs a handshake and then the full upload anyway, so
    /// a live path that is reliably broken makes every dictation slower than
    /// having the feature off. Three is enough to distinguish a bad afternoon
    /// from a bad build.
    public static let failureLimit = 3

    /// How long the pause lasts. A paused live path never gets the success that
    /// would clear its streak, so without a retry the pause was permanent until
    /// the user toggled the setting. After this long, one more attempt runs; a
    /// success clears the streak, a failure starts another pause.
    public static let retryAfter: TimeInterval = 10 * 60

    public var shouldStopTrying: Bool { shouldStopTrying(at: Date()) }

    public func shouldStopTrying(at now: Date) -> Bool {
        guard consecutiveFailures >= Self.failureLimit else { return false }
        guard let last = lastFailure else { return false }
        return now.timeIntervalSince(last) < Self.retryAfter
    }

    public var lastFailure: Date? {
        let raw = defaults.double(forKey: Self.lastFailureKey)
        return raw == 0 ? nil : Date(timeIntervalSinceReferenceDate: raw)
    }

    /// Clears the streak without clearing the history — used when the user turns
    /// live mode on again, which is an explicit "try once more".
    public func clearStreak() {
        defaults.set(0, forKey: Self.consecutiveKey)
    }

    public func reset() {
        defaults.removeObject(forKey: Self.attemptsKey)
        defaults.removeObject(forKey: Self.successesKey)
        defaults.removeObject(forKey: Self.consecutiveKey)
        defaults.removeObject(forKey: Self.lastFailureKey)
        for reason in Fallback.allCases {
            defaults.removeObject(forKey: Self.reasonPrefix + reason.rawValue)
        }
    }

    /// One honest line for the Settings footer.
    ///
    /// Names the dominant failure when there is one, because "live worked 40% of
    /// the time" is not actionable while "usually because the connection dropped"
    /// tells the user whether to blame their wifi or the feature.
    public var summary: String? {
        guard attempts > 0 else { return nil }
        let percent = Int((Double(successes) / Double(attempts) * 100).rounded())
        var line = "Used live for \(successes) of the last \(attempts) dictations (\(percent)%)."
        let worst = Fallback.allCases
            .map { ($0, count(of: $0)) }
            .filter { $0.1 > 0 }
            .max { $0.1 < $1.1 }
        if let worst, successes < attempts {
            line += " Most fell back because \(Self.phrase(for: worst.0))."
        }
        if shouldStopTrying, let last = lastFailure {
            let minutes = max(1, Int((Self.retryAfter - Date().timeIntervalSince(last)) / 60))
            line += " Paused after \(consecutiveFailures) failures in a row; tries again in \(minutes) min."
        }
        return line
    }

    static func phrase(for reason: Fallback) -> String {
        switch reason {
        case .neverOpened: return "the connection could not be opened"
        case .droppedMidSession: return "the connection dropped mid-sentence"
        case .truncated: return "audio arrived faster than it could be sent"
        case .noFinal: return "the transcript did not arrive in time"
        }
    }

    /// Maps a session's own explanation onto a coarse reason. The session's
    /// strings are for the log; these four are for the human.
    public static func classify(_ why: String) -> Fallback {
        let lowered = why.lowercased()
        if lowered.contains("truncated") || lowered.contains("dropped") { return .truncated }
        if lowered.contains("setup") || lowered.contains("connect") || lowered.contains("refused") {
            return .neverOpened
        }
        if lowered.contains("no final") { return .noFinal }
        return .droppedMidSession
    }
}
