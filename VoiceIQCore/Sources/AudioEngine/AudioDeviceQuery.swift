import AVFoundation
#if os(macOS)
import CoreAudio
#endif
import Foundation

#if os(macOS)
enum AudioDeviceQuery {
    static func defaultInputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        )
        return (status == noErr && deviceID != 0) ? deviceID : nil
    }

    /// How the default input is attached — built-in, Bluetooth, USB, aggregate.
    /// Logged because it is the single biggest predictor of capture-start latency
    /// (a Bluetooth HFP renegotiation is an order of magnitude slower than the
    /// built-in mic), so any deadline built on first-buffer timing must be a
    /// function of this, never a constant.
    static func transportDescription() -> String {
        guard let device = defaultInputDevice() else { return "no-device" }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &transport) == noErr else {
            return "unknown"
        }
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn: return "built-in"
        case kAudioDeviceTransportTypeBluetooth: return "bluetooth"
        case kAudioDeviceTransportTypeBluetoothLE: return "bluetooth-le"
        case kAudioDeviceTransportTypeUSB: return "usb"
        case kAudioDeviceTransportTypeAggregate: return "aggregate"
        case kAudioDeviceTransportTypeVirtual: return "virtual"
        case kAudioDeviceTransportTypeContinuityCaptureWired,
             kAudioDeviceTransportTypeContinuityCaptureWireless: return "continuity"
        case kAudioDeviceTransportTypeDisplayPort, kAudioDeviceTransportTypeHDMI: return "display"
        case kAudioDeviceTransportTypeThunderbolt: return "thunderbolt"
        case kAudioDeviceTransportTypeAirPlay: return "airplay"
        default: return "other"
        }
    }

    /// The device's current input sample rate and channel count, from the HAL.
    static func inputFormat(of device: AudioDeviceID) -> InputFormat? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var rate = Float64(0)
        var size = UInt32(MemoryLayout<Float64>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &rate) == noErr, rate > 0 else { return nil }
        address.mSelector = kAudioDevicePropertyStreamConfiguration
        address.mScope = kAudioObjectPropertyScopeInput
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size > 0 else { return nil }
        let list = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { list.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, list) == noErr else { return nil }
        let buffers = UnsafeMutableAudioBufferListPointer(list.assumingMemoryBound(to: AudioBufferList.self))
        return InputFormat(sampleRate: rate, channels: buffers.reduce(0) { $0 + $1.mNumberChannels })
    }

    // NOTE: device *pinning* (kAudioOutputUnitProperty_CurrentDevice or
    // AUAudioUnit.setDeviceID on the input node) was probed on macOS 26 and leaves
    // the engine running with a silent tap — do not reintroduce it on AVAudioEngine.
}
#else
/// iOS has no HAL device IDs: the audio session's route is the device. A
/// route change still has to read as "the mic switched", so the current input
/// port's UID stands in for the device ID.
typealias AudioDeviceID = Int

enum AudioDeviceQuery {
    static func defaultInputDevice() -> AudioDeviceID? {
        AVAudioSession.sharedInstance().currentRoute.inputs.first?.uid.hashValue
    }

    /// The session's current input format; the route stands in for the device.
    static func inputFormat(of _: AudioDeviceID) -> InputFormat? {
        let session = AVAudioSession.sharedInstance()
        guard session.sampleRate > 0, session.inputNumberOfChannels > 0 else { return nil }
        return InputFormat(sampleRate: session.sampleRate, channels: UInt32(session.inputNumberOfChannels))
    }

    static func transportDescription() -> String {
        guard let port = AVAudioSession.sharedInstance().currentRoute.inputs.first else { return "no-device" }
        switch port.portType {
        case .builtInMic: return "built-in"
        case .bluetoothHFP, .bluetoothLE: return "bluetooth"
        case .headsetMic: return "headset"
        case .usbAudio: return "usb"
        case .carAudio: return "car"
        default: return port.portType.rawValue
        }
    }
}

enum AudioInputDevices {
    static func currentDefaultName() -> String? {
        AVAudioSession.sharedInstance().currentRoute.inputs.first?.portName
    }
}
#endif

extension AudioDeviceQuery {
    struct InputFormat: Equatable {
        let sampleRate: Double
        let channels: UInt32
        init(sampleRate: Double, channels: UInt32) { self.sampleRate = sampleRate; self.channels = channels }
        init(_ format: AVAudioFormat) { self.init(sampleRate: format.sampleRate, channels: format.channelCount) }
        var description: String { "\(Int(sampleRate)) Hz/\(channels) ch" }
    }
}
