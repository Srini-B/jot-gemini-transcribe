# 2026-09-27 — iPhone app with a voice-only keyboard

## Why

The owner wants VoiceiQ on iPhone with the Typeless behaviour: a keyboard with
only voice input; the first mic tap bounces to the app once, and afterwards the
mic starts in place with the session shown in the Dynamic Island until the
user stops it. No mic indicator while idle, no idle-timeout setting, automatic
return to the previous app using the Dictus technique, and a record of every
app the keyboard is used in. Meetings run in the app as a recorder. Every Mac
setting that makes sense on a phone carries over, with the user's own API keys.

Research that shaped it: a teardown of the Typeless 2.7.0 IPA (keyboard pings
the app with a 250 ms timeout before each dictation, opens
`typeless://main/home?action=onStartVoiceRecording&hostAppBundleId=…` when it
gets no answer, returns via a native jump plus a bundle-ID → scheme table, with
a swipe-back screen as the fallback) and four open-source keyboards (Dictus,
Muesli, Handy, Bob). Research report: https://ordyse4h6ovt.postplan.dev

## Decisions

- Silent playback keeps the app alive between dictations, not a running input
  tap, because the owner observed Typeless shows no mic indicator while idle.
  Each dictation builds its own capture engine; the indicator shows only then.
- No idle timeout, per the owner. The session ends on End, when the Live
  Activity goes away (iOS caps it at eight hours), or on an unrecoverable
  interruption.
- Host detection uses Dictus's private-API approach (arbiter `+enabled`
  swizzle plus `_hostProcessIdentifier`), as the owner asked, adapted under
  MIT. Unknown apps fall back to the swipe-back screen and appear in
  Settings › Return to Apps, where a custom link can be added.
- `VoiceIQCore` stays one target: `#if os(macOS)` around 17 macOS-only files and
  the macOS-only parts of five others, plus small iOS stand-ins, instead of the target split proposed in the research.
  Splitting would have forced cross-module access changes through the macOS
  app for no behavioural gain.
- The keyboard links only the new `VoiceIQBridge` library: no network, keys or
  audio in the extension.
- `LiveTranscriber.makeFromSettings` moved from the Mac app into the core so
  both apps share it.
- `KeyShortcut.Modifier.genericMask` uses the raw `CGEventFlags` values
  (verified equal on macOS) so the file compiles on iOS.
- `scripts/build.sh` failed under `set -u` on machines with no signing
  certificate (empty array expansion in bash 3.2); fixed.

## Verification

- macOS: `scripts/build.sh` exit 0; `scripts/test.sh` 193 tests, 0 failures
  (same as before the change).
- iOS: `scripts/build-ios.sh` exit 0 (app, keyboard, Live Activity).
- iPhone 18 Pro Simulator, driven with AXe and a local mock of the Gemini
  endpoints (the Mac mini has no microphone, so Debug's
  `VOICEIQ_SIMULATED_MIC` fed a recorded phrase):
  - Keyboard added and Full Access granted through Settings; the app detected both.
  - Host detection resolved `com.apple.reminders`, `com.apple.MobileAddressBook`
    and the app itself.
  - Cold tap in Reminders: the app opened, started the session and the
    recording, then SpringBoard logged `Handling OpenURL from VoiceiQ:
    x-apple-reminderkit://` and Reminders came back.
  - Warm taps in Reminders recorded without leaving it; the keyboard showed
    Listening, the Dynamic Island a red waveform and timer; stop produced
    "Let's meet at 2 pm." in the reminder title, and a second dictation was
    appended with a space.
  - Lock screen Live Activity "VoiceiQ ready / Ready / End session"; Dynamic
    Island compact "Ready".
  - End in the app ended the session (phase `off`, keep-alive stopped).
  - Real `AudioCaptureEngine` on iOS (silent virtual mic) produced "Didn't
    catch that" through the normal silence gate.
  - A 42-second meeting recorded `mic.caf` (16 kHz mono), mixed, and finished
    as "No speech recorded".
- Not verified: the Dynamic Island and lock-screen buttons (the headless
  simulator would not take those taps), the swipe-back screen's appearance,
  Ask and Translate from the keyboard, anything on a physical iPhone
  (background survival over time, real mic, return links other than Reminders).
  In the simulator the first keep-alive start twice aborted inside Core Audio
  with an RPC timeout; it did not recur after a simulator reboot.

## Merge with 0.4.2–0.4.3 meetings, first TestFlight build (later the same day)

### What changed

- Pulled `origin/main` (0.4.2 speaker linking and meeting types, 0.4.3 WebRTC
  echo cancellation) on top of the iOS work. Two conflicts, both additive:
  `VoiceIQCore/Package.swift` and `THIRD_PARTY_NOTICES.md`.
- The AEC3 xcframework has a macOS slice only, so `CVoiceIQAEC` and `libc++`
  are linked on macOS only, `EchoCanceller.swift` is `#if os(macOS)`, and
  `MeetingTranscriber.callAudio` returns the raw mic on iOS. iOS meetings
  have no far side (the `SystemAudioTap` stand-in writes an empty
  `system.caf`), so there is nothing to cancel.
- The iOS `MeetingEngine` now gets the provider fallback order, as the Mac
  does. The iOS meeting detail shows the meeting type, the type-specific
  sections, suggested speaker names, timestamps, and a Redo menu.
- iOS targets moved to 0.4.3 (12) to match the Mac app.
- `Release` signs manually with Apple Distribution and three named App Store
  profiles. `ITSAppUsesNonExemptEncryption` is false. New
  `scripts/archive-ios.sh`.

### Apple accounts (team G8K3545FJ2, signed in as a team Admin)

- Registered the App Group and the three App IDs. Each ID has App Groups
  enabled and assigned. This was done in Chrome through Cua Driver.
- Created an Apple Distribution certificate from a CSR generated on the Mac
  mini. The key stays in `~/.voiceiq-signing` and a dedicated
  `voiceiq-signing` keychain on the Mac mini.
- Created three App Store provisioning profiles.
- Created the App Store Connect app "VoiceiQ Dictation". "VoiceiQ" was
  already taken.
- Created the internal TestFlight group "VoiceiQ Internal" with automatic
  distribution and no testers.
- asc (asccli.sh) could not be used. The account has no App Store Connect API
  access ("Request Access"), and `asc web` needs the Apple ID password and 2FA.

### Upload

- Archived and exported on the Mac mini (Xcode 27.0). `codesign --verify
  --deep --strict` passed. All three bundles carry the App Group,
  `beta-reports-active` and `get-task-allow` false.
- The Mac mini's Xcode has no signed-in account. The archive was uploaded from
  the MacBook, whose Xcode is signed in to the team. It ran as
  `xcodebuild -exportArchive` with `destination upload` inside the GUI session
  through a temporary LaunchAgent, because a plain SSH shell cannot unlock the
  login keychain.
- Result: 0.4.3 (12) uploaded, processed, "Ready to Submit", and attached to
  "VoiceiQ Internal".

### Verification

- `scripts/build.sh` exit 0.
- `scripts/test.sh` 193 tests, 0 failures.
- `scripts/build-ios.sh` exit 0.
- `scripts/archive-ios.sh` export succeeded.
- Not verified: the build on a physical iPhone, and App Review's view of the
  private host-detection API. TestFlight processing did not flag it.

### Open items

- The Account Holder must accept the updated Apple Developer Program License
  Agreement (App Store Connect banner). Until then, new submissions may be
  blocked.
- Add testers to "VoiceiQ Internal", or create an external group, which
  needs Beta App Review.

## asc setup and release scripts (later still)

The question was why the first setup did not use asc (https://asccli.sh).
It could not, for two reasons:

- The team has no App Store Connect API access. The API page shows "Request
  Access", which asks the Account Holder to accept Apple's API terms on
  behalf of Blue Lobster Technology. I opened that form and cancelled it
  without accepting.
- asc's other path is an Apple web session (`asc web ...`). App Groups, app
  records and API-key creation all go through it, and it needs the Apple
  Account password and a live two-factor code. I did not have either; Chrome
  already held a signed-in session.

What changed:

- asc 5.6.0 is installed on the Mac mini with Homebrew. Telemetry is
  disabled. No credentials are stored yet.
- `scripts/setup-asc.sh` is new. Run it once after API access is enabled: it
  signs in to the web session, creates an App Manager team key and stores it
  as the asc profile `voiceiq`.
- `scripts/release-ios.sh` is new. It runs preflight, tests, build number
  (from asc), `archive-ios.sh`, signature and entitlement checks, then
  `asc publish testflight --wait`. `UPLOAD=xcode` is the fallback that
  worked for build 12. `UPLOAD=none` is a dry run.
- `scripts/release.sh` now runs the `VoiceIQCore` tests first, matching
  `release-ios.sh`.
- `docs/RELEASING.md` covers both apps and the one-time steps. README and
  CONTRIBUTING describe the two-app layout, the build commands, the
  platform-guard convention and the release table.

Verification:

- `UPLOAD=none BUILD=13 scripts/release-ios.sh` passed: preflight, archive,
  export, signatures, App Group present, no `get-task-allow`.
- The default mode stops at preflight with the setup instruction, because no
  asc profile exists yet.
- `bash -n` passes on all changed scripts.
- Not run: `setup-asc.sh` and an asc upload (both need API access), and a
  macOS release (it would notarize).

### Correction and asc key (same evening)

My earlier note that the team had no API access was wrong. The Team Keys tab
already had an Admin key from May 2026, used by Expo EAS. The
"Request Access" form I saw earlier appears to be for individual keys only.

So asc (asccli.sh, installed with `brew install asc`, 5.6.0, the latest
release) could have done most of the first setup. Only one step needed the
browser: downloading a key. After that, asc could have registered the bundle
IDs and capabilities, created the certificate and profiles, uploaded the
build and managed the TestFlight group. Registering the App Group, assigning
it, and creating the app record would still have needed the portal or an
`asc web` session.

What I set up:

- Created the team key "VoiceiQ release" with the App Manager role.
- The `.p8` is in `~/.asc/keys` (0600).
- The key is registered as the asc profile `voiceiq` in `~/.asc/config.json`,
  because the login keychain is not writable from the agent session.
- Checked the profile with `apps view`, `builds list`,
  `builds next-build-number`, `testflight groups list`, `profiles list` and
  `certificates list`. All returned the expected data.

Script changes:

- `setup-asc.sh` takes an existing key (`KEY_FILE`, `ISSUER_ID`) or creates
  one through a web session. It falls back to config-file storage when the
  keychain is locked.
- `release-ios.sh` deletes the build-upload reservation that the App Store
  export creates ("awaiting upload"). My dry runs had left one for build 13;
  both were deleted.
