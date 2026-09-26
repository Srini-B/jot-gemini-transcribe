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

import AudioToolbox
import AVFoundation
import CoreAudio
import Foundation

public final class SystemAudioTap: @unchecked Sendable {
    public enum TapError: Error { case unsupported, coreAudio(OSStatus), format }
    private let url: URL
    private let queue = DispatchQueue(label: "com.ammaar.jot.meeting.system", qos: .userInitiated)
    private let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true)!
    private var tapID: AudioObjectID = kAudioObjectUnknown
    private var aggregateID: AudioObjectID = kAudioObjectUnknown
    private var procID: AudioDeviceIOProcID?
    private var inputFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var writer: CAFWriter?
    private var frames: Int64 = 0

    public init(url: URL) { self.url = url }

    public func start() throws {
        guard #available(macOS 14.2, *) else { throw TapError.unsupported }
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.uuid = UUID(); description.muteBehavior = .unmuted
        try check(AudioHardwareCreateProcessTap(description, &tapID))
        var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var stream = AudioStreamBasicDescription(), size = UInt32(MemoryLayout.size(ofValue: stream))
        try check(AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &stream))
        guard let input = AVAudioFormat(streamDescription: &stream), let converter = AVAudioConverter(from: input, to: target) else { throw TapError.format }
        inputFormat = input; self.converter = converter; writer = try CAFWriter(url: url, format: target); frames = 0
        let uid = UUID().uuidString
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Voice IQ Meeting Audio",
            kAudioAggregateDeviceUIDKey: uid,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString]],
        ]
        try check(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID))
        try check(AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { [weak self] _, inputData, _, _, _ in
            self?.consume(inputData)
        })
        try check(AudioDeviceStart(aggregateID, procID))
    }

    public func stop() -> Double {
        if aggregateID != kAudioObjectUnknown {
            _ = AudioDeviceStop(aggregateID, procID)
            if let procID { _ = AudioDeviceDestroyIOProcID(aggregateID, procID) }
            _ = AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if #available(macOS 14.2, *), tapID != kAudioObjectUnknown { _ = AudioHardwareDestroyProcessTap(tapID) }
        aggregateID = kAudioObjectUnknown; tapID = kAudioObjectUnknown; procID = nil
        queue.sync {}; writer?.close(); writer = nil; converter = nil; inputFormat = nil
        return Double(frames) / target.sampleRate
    }

    private func consume(_ list: UnsafePointer<AudioBufferList>) {
        guard let inputFormat, let buffer = AVAudioPCMBuffer(pcmFormat: inputFormat,
                                                             bufferListNoCopy: list, deallocator: nil),
              let converter, let writer else { return }
        let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * target.sampleRate / inputFormat.sampleRate))
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
        var supplied = false, error: NSError?
        let status = converter.convert(to: output, error: &error) { _, outStatus in
            if supplied { outStatus.pointee = .noDataNow; return nil }
            supplied = true; outStatus.pointee = .haveData; return buffer
        }
        guard status != .error, output.frameLength > 0 else { return }
        do { try writer.write(output); frames += Int64(output.frameLength) }
        catch { Log.meeting.error("system write failed: \(String(describing: error), privacy: .public)") }
    }

    private func check(_ status: OSStatus) throws { if status != noErr { throw TapError.coreAudio(status) } }
}
