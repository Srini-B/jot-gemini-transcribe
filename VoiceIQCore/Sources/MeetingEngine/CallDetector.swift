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

import AppKit
import ApplicationServices
import CoreAudio

/// Polls for an active call. A call is "active" when a known calling app, or a
/// browser showing a meeting page, is itself capturing the microphone. Mic
/// use is read per process (macOS 14.2+ Core Audio process objects), so Voice IQ's
/// own recording never counts as a call and a call that ends while the app
/// stays open is still noticed. Two consecutive hits start, three misses stop.
@MainActor public final class CallDetector {
    public var onChange: ((CallSource?) -> Void)?
    private var timer: Timer?, hits = 0, misses = 0
    private var active: CallSource?
    private nonisolated static let apps: [String: String] = ["us.zoom.xos": "Zoom", "com.microsoft.teams2": "Microsoft Teams",
        "com.microsoft.teams": "Microsoft Teams", "com.apple.FaceTime": "FaceTime", "net.whatsapp.WhatsApp": "WhatsApp",
        "com.tinyspeck.slackmacgap": "Slack", "com.hnc.Discord": "Discord", "com.cisco.webexmeetingsapp": "Webex",
        "Cisco-Systems.Spark": "Webex", "com.skype.skype": "Skype", "com.apple.MobileSMS": "Messages"]
    private nonisolated static let browserIDs = ["com.google.Chrome", "com.apple.Safari", "org.mozilla.firefox", "com.microsoft.edgemac",
                              "company.thebrowser.Browser", "com.brave.Browser", "com.vivaldi.Vivaldi", "com.operasoftware.Opera"]
    private nonisolated static let meetingNeedles = ["meet.google.com", "teams.microsoft.com", "teams.live.com", "zoom.us/j", "zoom.us/wc",
                                  "whereby.com", "app.slack.com/huddle", "discord.com/channels", "webex.com", "Meet - ",
                                  "| Microsoft Teams", "Zoom Meeting", "Huddle"]

    public init() {}
    public func start() { stop(); poll(); timer = .scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in Task { @MainActor in self?.poll() } } }
    public func stop() { timer?.invalidate(); timer = nil; hits = 0; misses = 0 }

    private var polling = false

    /// The Core Audio process walk and the AX window-title reads take up to
    /// ~100 ms and block on the inspected app, so they run off the main actor;
    /// only the hit/miss bookkeeping runs here.
    private func poll() {
        guard !polling else { return }
        polling = true
        Task { [weak self] in
            let source = await Task.detached(priority: .utility) { Self.detectedSource() }.value
            guard let self else { return }
            self.polling = false
            if source != nil {
                self.hits += 1; self.misses = 0
                if self.active == nil, self.hits >= 2 { self.active = source; self.onChange?(source) }
            } else {
                self.misses += 1; self.hits = 0
                if self.active != nil, self.misses >= 3 { self.active = nil; self.onChange?(nil) }
            }
        }
    }

    /// Processes with an active input stream. Browsers capture from helper
    /// processes (Chrome's `.helper`, Safari's `com.apple.WebKit.GPU` XPC
    /// service), so both the responsible app's pid and the helper's bundle ID
    /// are kept. Nil when the per-process API is unavailable (pre-14.2).
    private struct Capturing { var pids = Set<pid_t>(); var bundleIDs = Set<String>() }

    private nonisolated static func capturingProcesses() -> Capturing? {
        guard #available(macOS 14.2, *) else { return nil }
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return nil }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &objects) == noErr else { return nil }
        var result = Capturing()
        for object in objects {
            var flag: UInt32 = 0; var flagSize = UInt32(MemoryLayout<UInt32>.size)
            var running = Self.address(kAudioProcessPropertyIsRunningInput)
            guard AudioObjectGetPropertyData(object, &running, 0, nil, &flagSize, &flag) == noErr, flag != 0 else { continue }
            var pid: pid_t = 0; var pidSize = UInt32(MemoryLayout<pid_t>.size)
            var pidAddress = Self.address(kAudioProcessPropertyPID)
            if AudioObjectGetPropertyData(object, &pidAddress, 0, nil, &pidSize, &pid) == noErr, pid > 0 {
                result.pids.insert(pid)
                if let owner = Self.responsiblePID?(pid), owner > 0 { result.pids.insert(owner) }
            }
            var value: Unmanaged<CFString>? = nil; var valueSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            var bundle = Self.address(kAudioProcessPropertyBundleID)
            if AudioObjectGetPropertyData(object, &bundle, 0, nil, &valueSize, &value) == noErr, let id = value?.takeRetainedValue() {
                result.bundleIDs.insert(id as String)
            }
        }
        return result
    }

    private nonisolated static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    /// Maps an XPC helper (parent launchd) back to the app it works for. Same
    /// lookup TCC uses to attribute mic access; absent on some systems, hence optional.
    private nonisolated static let responsiblePID: (@convention(c) (pid_t) -> pid_t)? = {
        guard let symbol = dlsym(dlopen(nil, RTLD_NOW), "responsibility_get_pid_responsible_for_pid") else { return nil }
        return unsafeBitCast(symbol, to: (@convention(c) (pid_t) -> pid_t).self)
    }()

    private nonisolated static func isCapturing(_ app: NSRunningApplication, id: String, in capturing: Capturing) -> Bool {
        capturing.pids.contains(app.processIdentifier) || capturing.bundleIDs.contains { $0.hasPrefix(id) }
    }

    private nonisolated static func detectedSource() -> CallSource? {
        let capturing = capturingProcesses()
        // Pre-14.2: only a global "mic is in use" bit exists. Voice IQ's own meeting
        // tap trips it, so there the call ends only when the app or tab goes away.
        if capturing == nil, !microphoneInUse() { return nil }
        for app in NSWorkspace.shared.runningApplications {
            guard let id = app.bundleIdentifier, capturing.map({ isCapturing(app, id: id, in: $0) }) ?? true else { continue }
            if let name = apps[id] { return .app(bundleID: id, name: name) }
            let isBrowser = browserIDs.contains(id) || app.localizedName?.localizedCaseInsensitiveContains("Chrome") == true || app.localizedName?.localizedCaseInsensitiveContains("Chromium") == true
            if isBrowser, let host = matchingMeetingWindow(pid: app.processIdentifier) { return .browser(bundleID: id, host: host) }
        }
        return nil
    }

    private nonisolated static func matchingMeetingWindow(pid: pid_t) -> String? {
        let app = AXUIElementCreateApplication(pid); var value: CFTypeRef?
        AXUIElementSetMessagingTimeout(app, 1.0)
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return nil }
        for window in windows {
            var strings: [String] = []
            for key in [kAXTitleAttribute as String, kAXDocumentAttribute as String, "AXURL"] {
                var item: CFTypeRef?; if AXUIElementCopyAttributeValue(window, key as CFString, &item) == .success, let string = item as? String { strings.append(string) }
            }
            if let match = meetingNeedles.first(where: { needle in strings.contains { $0.localizedCaseInsensitiveContains(needle) } }) { return match }
        }
        return nil
    }

    private nonisolated static func microphoneInUse() -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(), size = UInt32(MemoryLayout.size(ofValue: device))
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr else { return false }
        address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var running: UInt32 = 0; size = UInt32(MemoryLayout.size(ofValue: running))
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running) == noErr && running != 0
    }
}
