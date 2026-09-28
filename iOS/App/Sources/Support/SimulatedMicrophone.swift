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
    /// With a live sink, the bytes delivered so far; stop saves only those,
    /// as a real microphone would.
    private var delivered: Int?

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
        // The live path gets the file as 16 kHz Int16 PCM, 100 ms per tick,
        // at the pace a microphone would deliver it.
        var pending = pcmSink.flatMap { _ in try? Self.pcm16k(source) } ?? Data()
        delivered = pcmSink == nil ? nil : 0
        var tick = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.onLevel?(Float.random(in: 0.2...0.6))
            tick += 1
            guard tick.isMultiple(of: 2), !pending.isEmpty, let pcmSink else { return }
            let chunk = pending.prefix(3_200)
            pending.removeFirst(chunk.count)
            self?.delivered? += chunk.count
            pcmSink(Data(chunk))
        }
    }

    private static func pcm16k(_ input: URL) throws -> Data {
        guard let buffer = try converted(input), let samples = buffer.int16ChannelData?[0] else { return Data() }
        return Data(bytes: samples, count: Int(buffer.frameLength) * 2)
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
        guard let buffer = try Self.converted(input) else { return 0 }
        if let delivered { buffer.frameLength = min(buffer.frameLength, AVAudioFrameCount(delivered / 2)) }
        try? FileManager.default.removeItem(at: output)
        let out = try AVAudioFile(forWriting: output, settings: buffer.format.settings, commonFormat: .pcmFormatInt16, interleaved: true)
        try out.write(from: buffer)
        return Int64(buffer.frameLength)
    }

    /// The file as 16 kHz mono Int16, the format the capture engine writes.
    private static func converted(_ input: URL) throws -> AVAudioPCMBuffer? {
        let file = try AVAudioFile(forReading: input)
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true)!
        guard let converter = AVAudioConverter(from: file.processingFormat, to: format),
              let inBuffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            return nil
        }
        try file.read(into: inBuffer)
        let capacity = AVAudioFrameCount(Double(inBuffer.frameLength) * 16_000 / file.processingFormat.sampleRate) + 1024
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var fed = false
        converter.convert(to: outBuffer, error: nil) { _, status in
            if fed { status.pointee = .endOfStream; return nil }
            fed = true; status.pointee = .haveData; return inBuffer
        }
        return outBuffer
    }
}
#endif
