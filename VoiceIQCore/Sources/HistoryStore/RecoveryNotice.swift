import Foundation

/// What the pill says when a dictation is recovered, and the text that goes on
/// the clipboard when the user asked for recovered dictations to be copied.
/// The History row is written either way; copying only adds a second home.
public enum RecoveryNotice {
    public enum Source: Equatable, Sendable {
        /// The launch scan transcribed the dictation a crash interrupted.
        case relaunch
        /// The retry queue finished this many queued dictations.
        case queue(count: Int)
        /// History's Retry transcribed a dictation again.
        case retry
    }

    public static func message(for source: Source, copied: Bool) -> String {
        switch source {
        case .relaunch:
            return copied
                ? "Recovered your last dictation — copied to the clipboard"
                : "Recovered your last dictation — it's in History"
        case .queue(let count) where count == 1:
            return copied
                ? "Your queued dictation is ready — copied to the clipboard"
                : "Your queued dictation is ready — it's in History"
        case .queue(let count):
            return copied
                ? "\(count) queued dictations are ready — copied to the clipboard"
                : "\(count) queued dictations are ready — they're in History"
        case .retry:
            return copied
                ? "Transcribed again — copied to the clipboard"
                : "Transcribed again — the new text is in History"
        }
    }

    /// Recovered texts in the order they were recovered, one paragraph each.
    /// Nil when there is nothing worth copying.
    public static func clipboardText(_ texts: [String]) -> String? {
        let paragraphs = texts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return paragraphs.isEmpty ? nil : paragraphs.joined(separator: "\n\n")
    }
}
