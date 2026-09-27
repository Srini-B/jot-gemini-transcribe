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

import AVFoundation
import Foundation

/// Transcripts of the chunks of one recording that have already come back,
/// keyed by the exact frame range each was cut at. A retry that chunks the
/// same CAF gets the same ranges and skips those requests; a different cut
/// (a changed chunk length, say) simply misses and re-sends. Lives next to
/// the audio as `chunks.json` and is deleted once every chunk is in.
struct ChunkTranscripts: Codable, Equatable {
    private var byRange: [String: String] = [:]

    var count: Int { byRange.count }

    subscript(range: Range<AVAudioFramePosition>) -> String? {
        get { byRange[Self.key(range)] }
        set { byRange[Self.key(range)] = newValue }
    }

    private static func key(_ range: Range<AVAudioFramePosition>) -> String {
        "\(range.lowerBound)-\(range.upperBound)"
    }

    static func read(from url: URL) -> ChunkTranscripts {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(ChunkTranscripts.self, from: data)
        else { return ChunkTranscripts() }
        return decoded
    }

    func write(to url: URL) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
