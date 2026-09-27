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

// Adapted from Dictus (github.com/getdictus/dictus-ios, MIT License,
// Copyright (c) 2026 PIVI Solutions). See THIRD_PARTY_NOTICES.md.

import ObjectiveC
import os
import UIKit

/// Which app the keyboard is typing into, so the app can send the user back
/// there after the one-time bounce. Uses private UIKit surfaces, all resolved at
/// runtime and guarded: a missing surface means no answer, never a crash.
///
/// Two facts are joined:
/// 1. `_UIKeyboardArbiterClient.currentClientState` names a (bundle ID, pid)
///    pair. On its own it is often stale (Dictus measured 7 of 16 appearances).
/// 2. `_hostProcessIdentifier` on our own input view controller is the host's
///    pid right now.
/// The arbiter's pairs go into a pid table; the current pid is looked up in it.
enum HostAppResolver {
    private static let arbiterClassNames = ["_UIKeyboardArbiterClient", "UIKeyboardArbiterClient"]
    private static let sharedClientSelector = "automaticSharedArbiterClient"
    private static var table = HostPidTable()
    private static let log = Logger(subsystem: "io.blue.voiceiq.ios.keyboard", category: "host")

    /// Call when the keyboard appears. Retires evidence from the last host.
    static func keyboardWillAppear() {
        table.noteAppearance()
        let activation = VIQHostArbiterActivation.activate()
        let connection = ensureArbiterConnection()
        log.info("arbiter \(activation, privacy: .public) (load \(VIQHostArbiterActivation.loadTimeOutcome(), privacy: .public)), connection \(connection, privacy: .public)")
        harvest()
    }

    /// Record what the arbiter says now. Cheap; call on every text change.
    static func harvest() {
        guard let state = currentClientState(),
              let bundleID = read("sourceBundleIdentifier", from: state) as? String,
              let pid = (read("processIdentifier", from: state) as? NSNumber)?.intValue
        else { return }
        table.record(bundleId: bundleID, forPid: pid)
    }

    /// The host's bundle ID, or nil when it cannot be known for certain.
    static func currentHost(for controller: UIInputViewController) -> String? {
        harvest()
        guard let pid = (read("_hostProcessIdentifier", from: controller) as? NSNumber)?.intValue, pid > 0 else {
            log.info("host unresolved: no host pid")
            return nil
        }
        guard let bundleID = table.bundleId(forPid: pid) else {
            log.info("host unresolved: pid \(pid) not in table (\(table.count) known)")
            return nil
        }
        return bundleID
    }

    private static func ensureArbiterConnection() -> String {
        guard let client = sharedClient() else { return "no-client" }
        guard read("connection", from: client) == nil else { return "connected" }
        let selector = NSSelectorFromString("startConnection")
        guard client.responds(to: selector) else { return "no-selector" }
        _ = client.perform(selector)
        return "started"
    }

    private static func currentClientState() -> NSObject? {
        sharedClient().flatMap { read("currentClientState", from: $0) as? NSObject }
    }

    private static func sharedClient() -> NSObject? {
        guard let cls = arbiterClassNames.lazy.compactMap({ NSClassFromString($0) as? NSObject.Type }).first else {
            return nil
        }
        let selector = NSSelectorFromString(sharedClientSelector)
        let classObject = cls as AnyObject
        guard classObject.responds(to: selector) else { return nil }
        return classObject.perform(selector)?.takeUnretainedValue() as? NSObject
    }

    private static func read(_ key: String, from object: NSObject) -> Any? {
        guard object.responds(to: NSSelectorFromString(key)) else { return nil }
        return object.value(forKey: key)
    }
}

/// Maps pids to bundle IDs and refuses to answer when the answer could be wrong.
///
/// iOS recycles pids and a keyboard process can live for hours, so an entry is
/// only trusted during the keyboard appearance that recorded it. A miss costs
/// the automatic return (the user swipes back instead); a wrong answer would
/// open an app the user was not in, which is worse.
struct HostPidTable {
    private struct Entry {
        let bundleId: String
        var generation: Int
    }

    static let maxEntries = 64
    private var entries: [Int: Entry] = [:]
    private var insertionOrder: [Int] = []
    private var generation = 0

    var count: Int { entries.count }

    mutating func noteAppearance() {
        generation &+= 1
    }

    mutating func record(bundleId: String, forPid pid: Int) {
        guard !bundleId.isEmpty, pid > 0 else { return }
        if entries[pid] == nil {
            insertionOrder.append(pid)
            if insertionOrder.count > Self.maxEntries {
                entries[insertionOrder.removeFirst()] = nil
            }
        }
        entries[pid] = Entry(bundleId: bundleId, generation: generation)
    }

    func bundleId(forPid pid: Int) -> String? {
        guard let entry = entries[pid], entry.generation == generation else { return nil }
        return entry.bundleId
    }
}
