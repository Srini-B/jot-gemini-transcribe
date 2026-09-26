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

public struct MeetingTranscriber: Sendable {
    private let client: GeminiClient
    public init(client: GeminiClient) { self.client = client }

    /// Speaker labels restart per chunk because the API does not preserve speaker identity across requests.
    public func transcribe(cafURL: URL, model: String, endpoint: URL,
                           deadline: TimeInterval) async throws -> [TranscriptSegment] {
        let file = try AVAudioFile(forReading: cafURL)
        let chunkFrames = AVAudioFramePosition(file.processingFormat.sampleRate * 25 * 60)
        var result: [TranscriptSegment] = []
        var start: AVAudioFramePosition = 0
        var index = 0
        while start < file.length {
            let end = min(file.length, start + chunkFrames)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("voiceiq-meeting-\(UUID()).flac")
            defer { try? FileManager.default.removeItem(at: url) }
            _ = try FLACEncoder.encode(cafURL: cafURL, flacURL: url, frameRange: start..<end)
            let words = try await client.transcribeDiarized(audio: Data(contentsOf: url), model: model,
                                                            endpoint: endpoint, deadline: deadline)
            result.append(contentsOf: Self.group(words: words, chunkIndex: index))
            start = end; index += 1
        }
        return result
    }

    public static func group(words: [DiarizedWord], chunkIndex: Int) -> [TranscriptSegment] {
        var segments: [TranscriptSegment] = []
        for word in words {
            let speaker = word.speaker ?? "speaker"
            if segments.last?.speaker == speaker {
                segments[segments.count - 1].text = append(word.text, to: segments.last!.text)
            } else {
                segments.append(TranscriptSegment(speaker: speaker, text: word.text, chunkIndex: chunkIndex))
            }
        }
        return segments
    }

    private static func append(_ word: String, to text: String) -> String {
        let punctuation = CharacterSet(charactersIn: ".,!?;:%)]}")
        if let scalar = word.unicodeScalars.first, punctuation.contains(scalar) { return text + word }
        return text.isEmpty ? word : text + " " + word
    }
}
