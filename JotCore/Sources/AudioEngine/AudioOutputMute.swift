// Copyright 2026 Google LLC
// Licensed under the Apache License, Version 2.0.

import CoreAudio
import Foundation

@MainActor
public final class AudioOutputMute {
    private enum Restore {
        case mute(AudioDeviceID)
        case volume(AudioDeviceID, Float32)
    }

    private var restore: Restore?

    public init() {}

    public func mute() {
        guard restore == nil, let device = defaultOutputDevice() else { return }
        if isMuted(device) { return }
        if setMute(true, on: device, onlyIfSettable: true) {
            restore = .mute(device)
            return
        }
        guard let volume = volume(on: device), setVolume(0, on: device) else {
            Log.audio.info("AudioOutputMute: output has no settable mute or volume")
            return
        }
        restore = .volume(device, volume)
    }

    public func unmute() {
        guard let restore else { return }
        self.restore = nil
        switch restore {
        case .mute(let device): _ = setMute(false, on: device, onlyIfSettable: false)
        case .volume(let device, let value): _ = setVolume(value, on: device)
        }
    }

    private func defaultOutputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != 0 else { return nil }
        return device
    }

    private func setMute(_ muted: Bool, on device: AudioDeviceID, onlyIfSettable: Bool) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var settable = DarwinBoolean(false)
        guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue else { return false }
        var current: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        if onlyIfSettable,
           AudioObjectGetPropertyData(device, &address, 0, nil, &size, &current) == noErr,
           current != 0 { return false }
        var value: UInt32 = muted ? 1 : 0
        return AudioObjectSetPropertyData(device, &address, 0, nil, size, &value) == noErr
    }

    private func isMuted(_ device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr && value != 0
    }

    private func volume(on device: AudioDeviceID) -> Float32? {
        var address = volumeAddress
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private func setVolume(_ volume: Float32, on device: AudioDeviceID) -> Bool {
        var address = volumeAddress
        var settable = DarwinBoolean(false)
        guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue else { return false }
        var value = volume
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value) == noErr
    }

    private var volumeAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }
}
