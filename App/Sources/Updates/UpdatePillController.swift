import AppKit
import Combine
import CoreGraphics
import VoiceIQCore

/// Puts a downloaded update on the pill with a Restart button, and installs it
/// on its own once nothing is recording and the Mac has been left alone for a
/// while, so an update never lands in the middle of a dictation or meeting.
@MainActor
final class UpdatePillController {
    /// Set by DictationController: paint a pill state.
    var setPill: (PillState) -> Void = { _ in }
    /// Set by DictationController: the pill currently shown.
    var currentPill: () -> PillState = { .idleDot }
    /// Set by DictationController: the pill to return to after the offer.
    var restingPill: () -> PillState = { .idleDot }
    /// Set by DictationController: a dictation, meeting, or answer is using the app.
    var sessionIsActive: () -> Bool = { false }
    /// Set by DictationController: a short notice on the pill.
    var notice: (String) -> Void = { _ in }

    /// No keyboard or mouse input for this long counts as the user being away.
    static let idleBeforeInstall: TimeInterval = 5 * 60
    private static let checkInterval: TimeInterval = 30
    private static let lastLaunchedVersionKey = "lastLaunchedVersion"

    private var updateObservation: AnyCancellable?
    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?
    /// The version already offered on the pill, so the offer shows once.
    private var offeredVersion: String?

    func bind() {
        updateObservation = AppUpdater.shared.$availableUpdate.sink { [weak self] update in
            self?.availableUpdateChanged(update)
        }
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: .pillUpdateRestartTapped, object: nil, queue: .main) { _ in
                Task { @MainActor in AppUpdater.shared.installDownloadedUpdate() }
            },
            center.addObserver(forName: .pillUpdateDismissed, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.withdrawOffer() }
            },
        ]
    }

    private func availableUpdateChanged(_ update: AppUpdater.AvailableUpdate?) {
        guard case .downloaded = update else {
            timer?.invalidate()
            timer = nil
            withdrawOffer()
            return
        }
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: Self.checkInterval, repeats: true) { _ in
                Task { @MainActor [weak self] in self?.check() }
            }
        }
        check()
    }

    private func check() {
        guard case let .downloaded(version) = AppUpdater.shared.availableUpdate,
              !sessionIsActive() else { return }
        if Self.secondsSinceUserInput() >= Self.idleBeforeInstall {
            AppUpdater.shared.installDownloadedUpdate()
            return
        }
        guard offeredVersion != version else { return }
        switch currentPill() {
        case .idleDot, .hidden:
            offeredVersion = version
            setPill(.updateReady(version))
        default:
            break // a notice or badge is up; offer on the next check
        }
    }

    private func withdrawOffer() {
        if case .updateReady = currentPill() { setPill(restingPill()) }
    }

    /// The relaunch after an update is otherwise silent. Call once the pill is
    /// on screen.
    func announceIfJustUpdated() {
        let defaults = UserDefaults.standard
        let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let previous = defaults.string(forKey: Self.lastLaunchedVersionKey)
        defaults.set(current, forKey: Self.lastLaunchedVersionKey)
        guard let previous, previous != current else { return }
        // The coordinator's first state arrives a beat after launch and repaints
        // the pill, so a notice shown straight away would vanish unseen.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            self?.notice("Updated to VoiceiQ \(current)")
        }
    }

    private static func secondsSinceUserInput() -> TimeInterval {
        let anyInput = CGEventType(rawValue: ~0)!
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }
}
