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

import UIKit
import VoiceIQBridge
import VoiceIQCore

/// Sends the user back to the app they were typing in after the one-time
/// bounce, and keeps a record of every app the keyboard was used in, so gaps in
/// the return table are visible and fixable from Settings.
@MainActor
final class HostReturn: ObservableObject {
    enum Outcome: String, Codable {
        /// Opened the app's return URL.
        case returned
        /// Had a URL, but iOS would not open it.
        case openFailed
        /// No URL known for this app. A gap in the table.
        case noScheme
        /// The app is known to have no way back (Safari, Spotlight).
        case noWayBack
        /// Dictated without leaving the app. No return needed.
        case inPlace

        var label: String {
            switch self {
            case .returned: return "Returns automatically"
            case .openFailed: return "Return failed"
            case .noScheme: return "No return link"
            case .noWayBack: return "Swipe back"
            case .inPlace: return "Used in place"
            }
        }
    }

    struct Record: Codable, Identifiable, Equatable {
        var id: String { bundleID }
        let bundleID: String
        var uses: Int
        var lastUsed: Date
        /// The outcome of the last bounce. `inPlace` never overwrites it.
        var lastReturn: Outcome?
    }

    @Published private(set) var records: [Record] = []
    @Published private(set) var overrides: [String: String] = [:]

    private static let recordsKey = "hostReturn.records"
    private static let overridesKey = "hostReturn.overrides"
    /// How long to wait for the recording to start before leaving the app.
    /// Leaving earlier than the engine start risks iOS refusing the mic.
    static let recordingWaitCeiling: TimeInterval = 0.6

    init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Self.recordsKey),
           let decoded = try? JSONDecoder().decode([Record].self, from: data) {
            records = decoded
        }
        overrides = defaults.dictionary(forKey: Self.overridesKey) as? [String: String] ?? [:]
    }

    static let ownBundleID = Bundle.main.bundleIdentifier ?? "io.blue.voiceiq.ios"

    func returnURL(for host: String) -> URL? {
        KnownAppSchemes.returnURL(forHostId: host, overrides: overrides)
    }

    /// Opens the host's return URL once `isRecording` says the mic is live (or
    /// the ceiling passes). Calls `completion(false)` when the user has to
    /// swipe back themselves.
    func returnToHost(_ host: String?, isRecording: @escaping () -> Bool, completion: @escaping (Bool) -> Void) {
        guard let host, host != Self.ownBundleID else {
            completion(host == Self.ownBundleID)
            return
        }
        guard let url = returnURL(for: host) else {
            note(host: host, outcome: KnownAppSchemes.knownNoSchemeHosts.contains(host) ? .noWayBack : .noScheme)
            completion(false)
            return
        }
        let deadline = Date().addingTimeInterval(Self.recordingWaitCeiling)
        func attempt() {
            guard isRecording() || Date() >= deadline else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { attempt() }
                return
            }
            UIApplication.shared.open(url, options: [:]) { [weak self] opened in
                self?.note(host: host, outcome: opened ? .returned : .openFailed)
                Log.session.info("return to \(host, privacy: .public): \(opened ? "opened" : "failed", privacy: .public)")
                completion(opened)
            }
        }
        attempt()
    }

    func note(host: String, outcome: Outcome) {
        guard host != Self.ownBundleID else { return }
        if let index = records.firstIndex(where: { $0.bundleID == host }) {
            records[index].uses += 1
            records[index].lastUsed = Date()
            if outcome != .inPlace { records[index].lastReturn = outcome }
        } else {
            records.append(Record(bundleID: host, uses: 1, lastUsed: Date(), lastReturn: outcome == .inPlace ? nil : outcome))
        }
        records.sort { $0.lastUsed > $1.lastUsed }
        save()
    }

    /// A user-supplied return URL for an app the table does not know.
    func setOverride(_ raw: String?, for host: String) {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        overrides[host] = trimmed.isEmpty ? nil : trimmed
        UserDefaults.standard.set(overrides, forKey: Self.overridesKey)
    }

    func forget(_ host: String) {
        records.removeAll { $0.bundleID == host }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: Self.recordsKey)
        }
    }
}
