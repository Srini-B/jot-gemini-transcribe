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

public enum AudioMixer {
    /// How much of a mono 16 kHz file is louder than room tone.
    ///
    /// MEASURED 2026-09-26 on mixed.caf files: 12 s of fan noise had 0.3 s of
    /// 100 ms windows above -42 dBFS and a 3.5 dB spread between its quiet and
    /// loud deciles; a 77 s call had 50 s above and a 17 dB spread; a 99 s
    /// dictation had 32 s above and a 12 dB spread.
    public struct SpeechStats: Equatable, Sendable {
        public var activeSeconds: Double
        public var spreadDB: Double
        /// Enough sound to be worth a transcription request. Fed silence, the
        /// diarizing model invents a word in a random language and the notes
        /// model then writes notes in that language.
        public var hasSpeech: Bool { activeSeconds >= 2 && spreadDB >= 6 }
    }

    public static func speechStats(url: URL) throws -> SpeechStats {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatInt16, interleaved: true)
        let window: AVAudioFrameCount = 1600
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 65_536)!
        var levels: [Double] = []
        var carry: [Int16] = []
        while file.framePosition < file.length {
            try file.read(into: buffer)
            guard let channel = buffer.int16ChannelData?[0] else { break }
            carry.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
            var start = 0
            while carry.count - start >= Int(window) {
                var sum = 0.0
                for sample in carry[start..<(start + Int(window))] {
                    let value = Double(sample) / 32768
                    sum += value * value
                }
                let rms = (sum / Double(window)).squareRoot()
                levels.append(20 * log10(max(rms, 1e-6)))
                start += Int(window)
            }
            carry.removeFirst(start)
        }
        guard levels.count >= 10 else { return SpeechStats(activeSeconds: 0, spreadDB: 0) }
        let sorted = levels.sorted()
        let active = Double(levels.filter { $0 > -42 }.count) * Double(window) / 16_000
        return SpeechStats(activeSeconds: active, spreadDB: sorted[sorted.count * 9 / 10] - sorted[sorted.count / 10])
    }
}
