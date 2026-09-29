import Foundation

/// Moves the single `smartFormatting` flag onto the two-flag formatting policy
/// introduced with native smart transcription.
///
/// Kept out of `LegacyMigration` on purpose: that file is scoped to the bundle
/// rename and says so. **This must run AFTER it** — `smartFormatting` is in
/// LegacyMigration's key list, so it has to be pulled out of the old defaults
/// domain before this reads it.
public enum FormattingSettingsMigration {
    private static let flag = "didMigrateSmartFormattingKeys"

    public static func runIfNeeded(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: flag) else { return }

        let previous = defaults.object(forKey: "smartFormatting") as? Bool
        let trips = (defaults.array(forKey: "gateTrips") as? [Date]) ?? []

        switch previous {
        case nil, .some(true):
            // Never touched it, or explicitly wanted smart output. Either way
            // they wanted formatting — native smart is now how that happens.
            defaults.set(true, forKey: "smartTranscription")
            defaults.set(false, forKey: "smartCleanupPass")
            Log.session.info("formatting migration: \(previous == nil ? "default" : "smart-on", privacy: .public) → native smart")

        case .some(false) where trips.count >= 3:
            // The auto-degrade fingerprint, and the threshold is exact rather
            // than "any trips": the OLD setSmartFormatting only cleared gateTrips
            // when ENABLING, so a user who deliberately chose verbatim keeps
            // whatever trips they had — up to 2, because the 3rd is precisely
            // what triggers auto-degrade. So >=3 means the app turned it off and
            // <=2 means the user did. They were degraded because the cleanup
            // MODEL was unreliable; native smart is a different mechanism
            // entirely and deserves a clean slate.
            defaults.set(true, forKey: "smartTranscription")
            defaults.set(false, forKey: "smartCleanupPass")
            defaults.removeObject(forKey: "gateTrips")
            defaults.set(true, forKey: "shouldAnnounceSmartRestored")
            Log.session.info("formatting migration: auto-degraded user → native smart, trips cleared")

        case .some(false):
            // No trips: a deliberate verbatim user. Never silently turn
            // formatting back on for someone who turned it off.
            defaults.set(false, forKey: "smartTranscription")
            defaults.set(false, forKey: "smartCleanupPass")
            Log.session.info("formatting migration: deliberate verbatim user preserved")
        }

        // Delete rather than leave behind: a downgrade→upgrade would otherwise
        // re-run this against a stale value, and the key would linger as a
        // second source of truth for something it no longer controls.
        defaults.removeObject(forKey: "smartFormatting")
        defaults.set(true, forKey: flag)
    }

    private static let writingRulesFlag = "didEnableWritingRules"

    /// Second one-time step, run AFTER `runIfNeeded`: switch the cleanup pass on
    /// for everyone who has formatting on at all. The pass is now what applies
    /// the user's writing rules (late corrections, grammar-driven sentence
    /// boundaries), so a stored `false` left behind by the first migration
    /// would silently strand them on native smart alone. A deliberate verbatim
    /// user (`smartTranscription == false`) keeps their choice.
    public static func enableWritingRulesIfNeeded(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: writingRulesFlag) else { return }
        defaults.set(true, forKey: writingRulesFlag)

        let verbatim = (defaults.object(forKey: "smartTranscription") as? Bool) == false
        guard !verbatim else {
            Log.session.info("writing rules migration: verbatim user preserved")
            return
        }
        defaults.set(true, forKey: "smartCleanupPass")
        Log.session.info("writing rules migration: cleanup pass enabled")
    }

    private static let undegradeFlag = "didRestoreAutoDegradedWritingRules"

    /// Fourth one-time step: writing rules no longer switch themselves off. The
    /// old auto-degrade turned them off on the third rejected rewrite within
    /// 24 hours and left those three trips in `gateTrips`; a user who turned
    /// them off by hand has fewer. Turn them back on for the first group, then
    /// drop the counter, which nothing reads any more.
    public static func restoreAutoDegradedWritingRulesOnce(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: undegradeFlag) else { return }
        defaults.set(true, forKey: undegradeFlag)
        let trips = (defaults.array(forKey: "gateTrips") as? [Date]) ?? []
        defaults.removeObject(forKey: "gateTrips")
        guard trips.count >= 3, (defaults.object(forKey: "smartCleanupPass") as? Bool) == false else { return }
        defaults.set(true, forKey: "smartCleanupPass")
        Log.session.info("writing rules migration: auto-degraded writing rules turned back on")
    }

    private static let liveOffFlag = "didDisableLiveTranscription"

    /// Third one-time step: live transcription becomes opt-in. Installs that
    /// had it on (the old default, stored or implied) are switched off once;
    /// whatever the user picks in Settings afterwards persists as usual.
    public static func disableLiveTranscriptionOnce(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: liveOffFlag) else { return }
        defaults.set(true, forKey: liveOffFlag)
        defaults.set(false, forKey: "liveTranscription")
        Log.session.info("live transcription migration: switched off, now opt-in")
    }
}
