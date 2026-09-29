#if os(macOS)
import AudioToolbox
import AVFoundation
import CoreAudio
import Foundation

/// Records the default input device to a 16 kHz mono CAF file.
///
/// Uses a Core Audio IOProc rather than AVAudioEngine: while `SystemAudioTap`'s
/// aggregate device is running, an AVAudioEngine input tap in this process
/// either miscounts frames or never fires (verified 2026-09-26). A direct
/// IOProc on the input device captures full length alongside the tap.
public final class MicTap: @unchecked Sendable {
    public enum MicError: Error { case coreAudio(OSStatus), format, noDevice }
    private let url: URL
    /// Receives every converted 16 kHz mono int16 buffer, on the IO queue. Set before `start()`.
    public var pcmSink: (@Sendable (Data) -> Void)?
    private let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000,
                                       channels: 1, interleaved: true)!
    /// IO callbacks run on `ioQueue`; start/stop/device moves run on `control` so that
    /// `AudioDeviceStop` never waits on the queue it is called from.
    private let ioQueue = DispatchQueue(label: "io.blue.voiceiq.meeting.mic.io", qos: .userInitiated)
    private let control = DispatchQueue(label: "io.blue.voiceiq.meeting.mic.control")
    private var deviceID: AudioDeviceID = kAudioObjectUnknown
    private var procID: AudioDeviceIOProcID?
    private var inputFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var writer: CAFWriter?
    private var frames: Int64 = 0
    private var listening = false
    private lazy var defaultInputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    private lazy var deviceListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        self?.control.async { self?.moveToDefaultDevice() }
    }

    public init(url: URL) { self.url = url }

    public func start() throws {
        writer = try CAFWriter(url: url, format: target); frames = 0
        try control.sync { try attach(to: Self.defaultInputDevice()) }
        _ = AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultInputAddress, control, deviceListener)
        listening = true
    }

    public func stop() -> Double {
        if listening {
            _ = AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defaultInputAddress, control, deviceListener)
            listening = false
        }
        control.sync { detach(); writer?.close(); writer = nil }
        Log.meeting.notice("mic stopped: frames=\(self.frames)")
        return Double(frames) / target.sampleRate
    }

    private func attach(to device: AudioDeviceID) throws {
        guard device != kAudioObjectUnknown else { throw MicError.noDevice }
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamFormat,
                                                 mScope: kAudioDevicePropertyScopeInput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var stream = AudioStreamBasicDescription(), size = UInt32(MemoryLayout.size(ofValue: stream))
        try check(AudioObjectGetPropertyData(device, &address, 0, nil, &size, &stream))
        guard let input = AVAudioFormat(streamDescription: &stream),
              let converter = AVAudioConverter(from: input, to: target) else { throw MicError.format }
        inputFormat = input; self.converter = converter; deviceID = device
        try check(AudioDeviceCreateIOProcIDWithBlock(&procID, device, ioQueue) { [weak self] _, inputData, _, _, _ in
            self?.consume(inputData)
        })
        try check(AudioDeviceStart(device, procID))
        Log.meeting.notice("mic started on device \(device): \(input.description, privacy: .public)")
    }

    private func detach() {
        if deviceID != kAudioObjectUnknown, let procID {
            _ = AudioDeviceStop(deviceID, procID)
            _ = AudioDeviceDestroyIOProcID(deviceID, procID)
        }
        ioQueue.sync {} // drain any in-flight callback before dropping its state
        deviceID = kAudioObjectUnknown; procID = nil; converter = nil; inputFormat = nil
    }

    /// Default input changed (headset plugged in, user switched mics): follow it.
    private func moveToDefaultDevice() {
        guard writer != nil else { return }
        let device = Self.defaultInputDevice()
        guard device != deviceID else { return }
        detach()
        do { try attach(to: device); Log.meeting.notice("mic moved to device \(device) (frames=\(self.frames))") }
        catch { Log.meeting.error("mic move failed: \(String(describing: error), privacy: .public)") }
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
        catch { Log.meeting.error("mic write failed: \(String(describing: error), privacy: .public)") }
        if let pcmSink, let channel = output.int16ChannelData {
            pcmSink(Data(bytes: channel[0], count: Int(output.frameLength) * 2))
        }
    }

    private static func defaultInputDevice() -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(kAudioObjectUnknown), size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr ? device : kAudioObjectUnknown
    }

    private func check(_ status: OSStatus) throws { if status != noErr { throw MicError.coreAudio(status) } }
}
#endif
