# VoiceiQ for iOS

A voice-only keyboard backed by the same dictation pipeline as the Mac app.
The keyboard never records or calls a model. It sends commands to the VoiceiQ
app, which records, transcribes with your own API key, and hands the text back.

## Targets

| Target | Bundle ID | Contents |
| --- | --- | --- |
| `VoiceIQiOS` | `io.blue.voiceiq.ios` | App: onboarding, keys, settings, history, meetings, background voice session |
| `VoiceIQKeyboard` | `io.blue.voiceiq.ios.keyboard` | Keyboard extension (`RequestsOpenAccess`), links `VoiceIQBridge` only |
| `VoiceIQLiveActivity` | `io.blue.voiceiq.ios.liveactivity` | Dynamic Island and lock-screen Live Activity |

All three share the App Group `group.io.blue.voiceiq`. The app declares
`UIBackgroundModes: audio` and `NSSupportsLiveActivities`, and handles the
`voiceiq://` scheme. Minimum iOS is 17 (Live Activity buttons need
`LiveActivityIntent`).

`VoiceIQCore` builds for iOS and macOS. Files that need AppKit, Accessibility,
event taps, ScreenCaptureKit or Core Audio HAL are wrapped in `#if os(macOS)`.
iOS gets small stand-ins where the shared coordinator expects a type:
`SessionCoordinator/PlatformStubs+iOS.swift` (no screen context, no secure
input) and `MeetingEngine/MeetingCapture+iOS.swift` (an `AVAudioEngine` mic
tap, an empty system-audio file, no call detection). `VoiceIQBridge` is a
second, extension-safe library in the same package.

## How a dictation works

```
Keyboard ──command + Darwin ping──▶ App Group ──▶ App (background audio)
   ▲                                                   │ DictationCoordinator
   └──────snapshot + Darwin ping ◀── App Group ◀───────┘ → Gemini / gateways
```

`VoiceIQBridge` defines the protocol:

- `KeyboardCommand` (`start` with a mode, `stop`, `cancel`), written only by the keyboard.
- `SessionSnapshot` (`off`, `warm`, `recording`, `processing`, plus the last
  `Delivery` and `Notice`), written only by the app.
- `ActivityRequest`, written only by the Live Activity buttons.
- A heartbeat the app writes every second while a session is up.

Every key has one writer, so nothing is locked. Darwin notifications
(`io.blue.voiceiq.bridge.command`, `…state`) carry no data. They only mean
"reread the App Group". Both sides also reread on their own lifecycle events,
because pings are dropped while a process is suspended.

### Mic tap

1. The keyboard resolves the host app (below), writes a `start` command and pings.
2. If the heartbeat is fresh (under 3 s), the app is running. The keyboard waits
   up to 0.7 s for the app to acknowledge the command. The app starts recording
   from the background. No app switch.
3. Otherwise, or without an acknowledgement, the keyboard opens
   `voiceiq://keyboard/start?cmd=<id>&host=<bundle id>`. The app starts the
   background session in the foreground (iOS refuses to activate audio from the
   background), starts the dictation, waits until the mic is live (0.6 s at
   most), and opens the host's return URL. With no return URL it shows
   "Swipe right along the bottom edge to go back".
4. Stop sends `stop`. The app transcribes, writes a `Delivery`, and pings. The
   keyboard inserts the text with `textDocumentProxy.insertText`, adding a space
   when it would run into the previous word. A result finished for a different
   app, or more than two minutes ago, is not typed; Paste last still has it.

Ask shows the answer in a panel with Insert and Copy. Translate inserts the
translation into the target language from Settings › Dictation.

### The background session

`KeepAliveAudio` sets a `.playAndRecord` session (mix with others, A2DP; HFP
only when "Use iPhone microphone" is off) and plays silence through a
playback-only `AVAudioEngine`. It never touches `inputNode`, so the orange mic
indicator stays off between dictations. Each dictation builds its own capture
engine (`AudioCaptureEngine`), which lights the indicator only while recording.

The session ends when the user taps End (app or Dynamic Island), when the Live
Activity is dismissed or ended by iOS (iOS caps a Live Activity at eight hours),
or when an audio interruption cannot be resumed. There is no idle timeout.
A call or Siri interruption finalizes an in-progress dictation, so the words
are kept.

### Returning to the host app

`HostAppResolver` (keyboard) joins two private UIKit surfaces, adapted from
Dictus: `_UIKeyboardArbiterClient.currentClientState` gives (bundle ID, pid)
pairs once its `+enabled` class method is forced to `YES` at load time
(`HostArbiterActivation.m`), and `_hostProcessIdentifier` on the input view
controller gives the current host pid. Pairs are only trusted during the
keyboard appearance that recorded them, so a recycled pid can cause a miss but
never a wrong app. Every surface is resolved at runtime; a missing one means no
automatic return, never a crash.

`KnownAppSchemes` (in `VoiceIQBridge`) maps bundle IDs to URLs that resume the
app where the user left it: the Dictus table plus 14 apps from the Typeless
2.7.0 table. The app opens it with `UIApplication.open`, which needs no
`LSApplicationQueriesSchemes`.

Settings › Return to Apps lists every app the keyboard was used in, with how
the last bounce went. An app with no link can be given a custom one there;
custom links take precedence over the table.

### Meetings

Meetings run in the app like a recorder: Record meeting, the phone records the
room with the mic, Stop, then `MeetingEngine` transcribes and writes notes. The
Live Activity shows the running time with a Stop button. iOS does not allow
recording other apps' or call audio, so `SystemAudioTap` writes an empty
`system.caf` and the pipeline treats every meeting as in-person: there is no
far-side reference, so `MeetingTranscriber.callAudio` skips echo cancellation
(the WebRTC AEC3 xcframework ships a macOS slice only and is not linked on
iOS). Speaker linking, meeting-type notes, suggested speaker names and Redo
(notes only, or transcript and notes) work as on the Mac. Dictation is refused
while a meeting records.

## Feature parity with macOS

| macOS | iOS |
| --- | --- |
| Dictation key, hands-free | Mic button in the keyboard |
| Pill | Keyboard status plus Dynamic Island |
| AX and paste insertion | `textDocumentProxy.insertText` |
| Ask Anything, Translate, Paste last | Keyboard modes and Paste last |
| Providers, keys, TinyFish | Same, in the iOS Keychain |
| Dictionary, writing rules, smart transcription, live, noise handling | Same settings |
| History, retry, crash recovery, retention | Same |
| Cost | Same ledger |
| Screen context, auto-learn, shortcuts, call detection, mute other audio, sounds | Not on iOS |

## Building

```bash
./scripts/build-ios.sh                              # Simulator, ad-hoc signed
./scripts/build-ios.sh DEVICE=1 DEVELOPMENT_TEAM=XXXXXXXXXX
```

A device build needs the App Group `group.io.blue.voiceiq` registered for all
three bundle IDs under your team.

### Apple Developer setup (team G8K3545FJ2)

| Item | Value |
| --- | --- |
| App Group | `group.io.blue.voiceiq` ("VoiceiQ Shared") |
| App IDs, each with App Groups → `group.io.blue.voiceiq` | `io.blue.voiceiq.ios`, `io.blue.voiceiq.ios.keyboard`, `io.blue.voiceiq.ios.liveactivity` |
| App Store profiles (`Release` uses these by name) | `VoiceiQ iOS App Store`, `VoiceiQ Keyboard App Store`, `VoiceiQ Live Activity App Store` |
| Signing identity | `Apple Distribution: Blue Lobster Technology PTE. LTD (G8K3545FJ2)` |
| App Store Connect app | "VoiceiQ Dictation", Apple ID 6816685189, SKU `voiceiq-ios` ("VoiceiQ" was taken) |

If a capability changes, the three profiles are invalidated and must be
regenerated in the portal under the same names.

### TestFlight

```bash
./scripts/release-ios.sh                # test, archive, verify, upload with asc
UPLOAD=none ./scripts/release-ios.sh    # stop before the upload
```

The steps, the one-time asc and signing setup, and the Xcode upload fallback
are in [RELEASING.md](RELEASING.md#iphone-testflight). `ITSAppUsesNonExemptEncryption`
is `false`, so builds skip the export-compliance question.

## Known limits

- The host-app resolver and the arbiter swizzle are private API. App Review may
  reject them; if it does, delete `HostArbiterActivation.m` and the resolver
  returns nil, which falls back to the swipe-back screen.
- iOS ends a Live Activity after eight hours, which ends the session. The next
  mic tap bounces once.
- The first dictation after a cold start costs one trip to the app.
