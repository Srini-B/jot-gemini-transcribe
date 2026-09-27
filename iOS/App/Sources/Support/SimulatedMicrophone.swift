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

#if DEBUG
import AVFoundation
import VoiceIQCore

/// Debug builds only: plays a recorded file as the microphone, so the whole
/// keyboard → app → model → keyboard path can run in a Simulator on a Mac with
/// no microphone. Set `VOICEIQ_SIMULATED_MIC` to an audio file path at launch
/// (`SIMCTL_CHILD_VOICEIQ_SIMULATED_MIC=… xcrun simctl launch …`).
final class SimulatedMicrophone: AudioCapturing {
    var onLevel: ((Float) -> Void)?
    var onDeviceChange: ((String) -> Void)?
    var onWriteFailure: (() -> Void)?
    var onEngineDied: ((String) -> Void)?

    private let source: URL
    private var target: URL?
    private var timer: Timer?

    static func make() -> AudioCapturing? {
        guard let path = ProcessInfo.processInfo.environment["VOICEIQ_SIMULATED_MIC"],
              FileManager.default.fileExists(atPath: path) else { return nil }
        return SimulatedMicrophone(source: URL(fileURLWithPath: path))
    }

    private init(source: URL) {
        self.source = source
    }

    func start(writingTo url: URL, pcmSink: (@Sendable (Data) -> Void)?) throws {
        target = url
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.onLevel?(Float.random(in: 0.2...0.6))
        }
    }

    func stop() async -> AudioCaptureResult {
        timer?.invalidate()
        timer = nil
        guard let target, let frames = try? convert(source, to: target) else {
            return AudioCaptureResult(framesWritten: 0, durationSeconds: 0)
        }
        return AudioCaptureResult(framesWritten: frames, durationSeconds: Double(frames) / 16_000,
                                  peakLevel: 0.5, writtenPeakLevel: 0.5)
    }

    private func convert(_ input: URL, to output: URL) throws -> Int64 {
        let file = try AVAudioFile(forReading: input)
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true)!
        try? FileManager.default.removeItem(at: output)
        let out = try AVAudioFile(forWriting: output, settings: format.settings, commonFormat: .pcmFormatInt16, interleaved: true)
        guard let converter = AVAudioConverter(from: file.processingFormat, to: format),
              let inBuffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            return 0
        }
        try file.read(into: inBuffer)
        let capacity = AVAudioFrameCount(Double(inBuffer.frameLength) * 16_000 / file.processingFormat.sampleRate) + 1024
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return 0 }
        var fed = false
        converter.convert(to: outBuffer, error: nil) { _, status in
            if fed { status.pointee = .endOfStream; return nil }
            fed = true; status.pointee = .haveData; return inBuffer
        }
        try out.write(from: outBuffer)
        return Int64(outBuffer.frameLength)
    }
}
#endif
