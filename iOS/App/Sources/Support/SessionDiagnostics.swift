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
import VoiceIQCore

/// The last few hundred session events (keeper, background mic starts), kept
/// in a file so a TestFlight user can copy them from Settings › Advanced.
/// No transcript text or keys go in here.
enum SessionDiagnostics {
    private static let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("session-log.txt")
    private static let queue = DispatchQueue(label: "io.blue.voiceiq.session-log")
    private static let maxLines = 400

    static func note(_ line: String) {
        Log.session.info("\(line, privacy: .public)")
        let stamp = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withTime, .withColonSeparatorInTime])
        queue.async {
            var lines = (try? String(contentsOf: url, encoding: .utf8))?.split(separator: "\n", omittingEmptySubsequences: true).map(String.init) ?? []
            lines.append("\(stamp) \(line)")
            if lines.count > maxLines { lines.removeFirst(lines.count - maxLines) }
            try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        }
    }

    static func read() -> String {
        queue.sync { (try? String(contentsOf: url, encoding: .utf8)) ?? "" }
    }

    static func clear() {
        queue.sync { try? FileManager.default.removeItem(at: url) }
    }
}
