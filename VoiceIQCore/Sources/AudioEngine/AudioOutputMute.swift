// Copyright 2026 Google LLC
// Licensed under the Apache License, Version 2.0.

import CoreAudio
import Foundation

/// Mutes the default output while the user dictates and puts it back after.
///
/// The debt (which device, how to restore it) is persisted in UserDefaults and
/// keyed by device UID, not `AudioDeviceID`: IDs are per-boot and change when a
/// Bluetooth route flips profile, and a crash or force-quit mid-dictation used
/// to leave the speaker muted with nobody remembering why. `settle()` runs at
/// launch and whenever the device list changes, so a muted device is repaired
/// as soon as it is reachable again.
@MainActor
public final class AudioOutputMute {
    private struct Debt: Codable, Equatable {
        enum Kind: String, Codable { case mute, volume }
        var uid: String
        var kind: Kind
        var volume: Float32
    }

    private static let defaultsKey = "audioOutputMuteDebt"

    private var debt: Debt? {
        didSet {
            guard debt != oldValue else { return }
            if let debt, let data = try? JSONEncoder().encode(debt) {
                UserDefaults.standard.set(data, forKey: Self.defaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
            }
        }
    }

    /// True between `mute()` and `unmute()`. A device change in this window
    /// moves the mute to the new default output.
    private var active = false

    public init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let saved = try? JSONDecoder().decode(Debt.self, from: data) {
            debt = saved
        }
        settle()
        observeDevices()
    }

    public func mute() {
        active = true
        guard debt == nil, let device = defaultOutputDevice() else { return }
        applyMute(to: device)
    }

    public func unmute() {
        active = false
        settle()
        if let debt {
            Log.audio.error("AudioOutputMute: could not restore \(debt.uid, privacy: .public) — device absent, will retry when it returns")
        }
    }

    /// Repay the outstanding debt if its device is present. Safe to call at
    /// any time; a no-op when there is nothing to repay.
    public func settle() {
        guard let debt, let device = self.device(forUID: debt.uid) else { return }
        let ok: Bool
        switch debt.kind {
        case .mute:
            ok = setMute(false, on: device) && !isMuted(device)
        case .volume:
            ok = setVolume(debt.volume, on: device)
        }
        if ok {
            self.debt = nil
        } else {
            Log.audio.error("AudioOutputMute: restore failed on \(debt.uid, privacy: .public) (\(debt.kind.rawValue, privacy: .public))")
        }
    }

    // MARK: - Device changes

    private func observeDevices() {
        for selector in [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDevices] {
            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectAddPropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main
            ) { [weak self] _, _ in
                Task { @MainActor in self?.handleDeviceChange() }
            }
        }
    }

    private func handleDeviceChange() {
        settle()
        // Dictation still running and the output moved: mute the new route so
        // music does not burst out of AirPods that just connected.
        guard active, debt == nil, let device = defaultOutputDevice() else { return }
        applyMute(to: device)
    }

    // MARK: - Apply

    private func applyMute(to device: AudioDeviceID) {
        guard let uid = uid(of: device) else { return }
        if isMuted(device) { return }
        if muteIsSettable(device), setMute(true, on: device) {
            debt = Debt(uid: uid, kind: .mute, volume: 0)
            return
        }
        guard let volume = volume(on: device), setVolume(0, on: device) else {
            Log.audio.info("AudioOutputMute: output has no settable mute or volume")
            return
        }
        debt = Debt(uid: uid, kind: .volume, volume: volume)
    }

    // MARK: - CoreAudio

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

    private func uid(of device: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr,
              let uid = value?.takeRetainedValue() else { return nil }
        return uid as String
    }

    private func device(forUID uid: String) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var cfUID = uid as CFString
        var device: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = withUnsafeMutablePointer(to: &cfUID) { qualifier in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject), &address,
                UInt32(MemoryLayout<CFString>.size), qualifier, &size, &device
            )
        }
        guard status == noErr, device != kAudioObjectUnknown else { return nil }
        return device
    }

    private var muteAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private var volumeAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private func muteIsSettable(_ device: AudioDeviceID) -> Bool {
        var address = muteAddress
        var settable = DarwinBoolean(false)
        return AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
    }

    private func setMute(_ muted: Bool, on device: AudioDeviceID) -> Bool {
        var address = muteAddress
        var value: UInt32 = muted ? 1 : 0
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
    }

    private func isMuted(_ device: AudioDeviceID) -> Bool {
        var address = muteAddress
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
}
