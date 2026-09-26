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
    public static func mixToMono(micURL: URL, systemURL: URL, outputURL: URL) throws -> Double {
        let mic = try AVAudioFile(forReading: micURL, commonFormat: .pcmFormatInt16, interleaved: true)
        let system = try AVAudioFile(forReading: systemURL, commonFormat: .pcmFormatInt16, interleaved: true)
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true)!
        try? FileManager.default.removeItem(at: outputURL)
        let output = try AVAudioFile(forWriting: outputURL, settings: format.settings,
                                     commonFormat: .pcmFormatInt16, interleaved: true)
        let total = max(mic.length, system.length)
        let capacity: AVAudioFrameCount = 65_536
        var position: AVAudioFramePosition = 0
        while position < total {
            let count = AVAudioFrameCount(min(AVAudioFramePosition(capacity), total - position))
            let a = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count)!
            let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count)!
            if position < mic.length { mic.framePosition = position; try mic.read(into: a, frameCount: AVAudioFrameCount(min(Int64(count), mic.length - position))) }
            if position < system.length { system.framePosition = position; try system.read(into: b, frameCount: AVAudioFrameCount(min(Int64(count), system.length - position))) }
            let mixed = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count)!
            mixed.frameLength = count
            let ap = a.int16ChannelData![0], bp = b.int16ChannelData![0], mp = mixed.int16ChannelData![0]
            for i in 0..<Int(count) {
                let av = i < Int(a.frameLength) ? Int(ap[i]) : 0
                let bv = i < Int(b.frameLength) ? Int(bp[i]) : 0
                mp[i] = Int16(clamping: (av + bv) / 2)
            }
            try output.write(from: mixed)
            position += AVAudioFramePosition(count)
        }
        return Double(total) / format.sampleRate
    }
}
