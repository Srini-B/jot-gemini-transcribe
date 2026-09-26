# 2026-09-26 — Speaker stays muted after dictation; AVAudioEngine device-change crash

## Report

The speaker is muted correctly when dictation starts but sometimes stays muted after it ends.

## Investigation

- Direct reproduction of the normal paths failed: 5 start/stop cycles, Esc cancel, and Ask Anything all restored `kAudioDevicePropertyMute` to 0 within 100 ms of key-up. A 6 s, 100 ms-resolution watch after stop showed no re-mute from the capture engine's late teardown.
- Two crash reports from today (`Voice IQ-2026-09-26-140210.ips`, `-180456.ips`) are `EXC_BAD_ACCESS` in `AVAudioIOUnit::IOUnitPropertyListener` on the `AVAudioIOUnit` queue. The main thread in both is `WarmEnginePool.refresh()` → `AudioCaptureEngine.deinit` → `-[AVAudioEngine dealloc]`, called from the default-input-changed observer. Unified log shows "HAL notification: default output device changed" immediately before each crash. A crash mid-dictation leaves the output muted and the old `AudioOutputMute` had no memory of it: on the next launch `mute()` saw the device already muted and left it alone, so the user had to unmute by hand.
- The old restore also targeted the `AudioDeviceID` captured at mute time. Those IDs are per-boot and change when a Bluetooth route flips profile, so a device change during dictation made the restore a silent no-op.

## Fix

- `AudioOutputMute` now persists its debt (device UID, mute or volume, saved volume) in `UserDefaults` and repays it through `settle()` at launch, on `unmute()`, and on every default-output or device-list change. If the output moves during dictation the old route is restored and the new one muted.
- `WarmEnginePool.refresh()` and `AudioCaptureEngine.tearDownEngine()` hold the dropped `AVAudioEngine` for 5 s before releasing it, so AVFAudio's asynchronously dispatched listener block runs against a live object.

## Verification

- Release build installed. Normal cycle: mute=1 during, mute=0 after, `audioOutputMuteDebt` present during and absent after.
- Crash scenario: `kill -9` mid-dictation left mute=1; relaunching the app restored mute=0 within 5 s and cleared the debt.
- The device-change race itself could not be exercised on this machine (single output device). The crash fix follows from the stack traces, not from a reproduction.
- `./scripts/build.sh` clean.

# Same day — pill follows the pointer across displays

## Why

With two displays, dictation started on one screen while the user reads from the other left the pill behind. The pill used to pick the focused window's screen once per session and stay there.

## Change

`PillHUDController` installs a global `.mouseMoved`/`.leftMouseDragged` monitor while the panel is ordered in. When the pointer's screen differs from the panel's, the panel is re-placed at that screen's bottom-center. `targetScreen()` now prefers the pointer's display; the focused window's screen is only a fallback for a pointer that is on no display.

## Verification

Release build installed on a two-display setup (LG 2560×1440 primary, built-in Retina to its right). Pointer warped between displays mid-dictation with synthetic mouse events: the panel moved within 300 ms each way, landing at x=980,y=1328 (LG) and x=2980,y=1160 (built-in), both bottom-center. Session start places on the pointer's display; stop leaves it there.

# Same day — product name is one word: VoiceiQ

## Why

The user spelled the name `VoiceiQ` on the About pane earlier; the onboarding "Talk to Voice IQ." heading, README, docs, scripts and Info.plist still used two words.

## Change

`Voice IQ` and `Voice-IQ` became `VoiceiQ` in every tracked file outside `activities/` (34 files: `project.yml`, `App/Info.plist`, UI strings, Keychain item labels, the meeting aggregate-device name, release and DMG scripts, README, docs). The bundle id `io.blue.voiceiq` and the Keychain service are unchanged. `PRODUCT_NAME` changed too, so the app is now `/Applications/VoiceiQ.app` and release artifacts are `VoiceiQ-<version>.dmg/.zip`.

The Application Support folder moved from `Voice IQ` to `VoiceiQ`. `FileLayout.appSupportRoot` now walks a list of legacy names (`Voice IQ`, then `Jot`) and moves the first one found when the new folder is absent.

## Incident during rollout

The first release build failed to migrate: the bulk `sed` had also rewritten the legacy folder name inside the new migration list, so the app looked for `VoiceiQ` as the legacy name and created an empty store instead. A stray empty `VoiceiQ` folder from 10:24 (0 dictations) masked this on the first launch. Fixed the literal, deleted the empty folder, rebuilt.

## Verification

- `./scripts/build.sh` clean; 193 package tests pass.
- Notarized release installed as `/Applications/VoiceiQ.app`; the old `Voice IQ.app` removed. Accessibility and the hotkey event tap survived the rename (`EventTapEngine: tap running (key=rightOption)`).
- Launch moved `~/Library/Application Support/Voice IQ` to `VoiceiQ`; `history.sqlite` reports 108 dictations.
- Onboarding how-to screen reads "Talk to VoiceiQ."; About pane shows icon, `VoiceiQ`, `Version 0.4.0 (9)`. Onboarding flag left true.

# Same day — auto-learn: wait for the edit to finish, learn words not rules

## Why

Editing "Paystack" to "pstack" in Amp after a dictation produced two auto entries two seconds apart: `Paystack → Pastack` (learned while the word was half typed) and `stack → pstack`. Both were stored as wrong→right rules, which `ReplacementEngine` applies to every later transcript, so any future "stack" would have become "pstack".

## Change

- `EditLearner` diffs a changed field only after its value has stayed the same for 4 s (`settleSeconds`). Each poll that sees a new value records it as pending; the diff runs on the first poll after the value has held still. Insertion resets the pending state.
- Learned corrections are stored as `DictionaryEntry(term: replacement, learnedFrom: original, source: .auto)` with no `misspelling`, so they join the vocabulary but never form a replacement rule or a prompt spelling hint. `DictionaryEntry.init(from:)` demotes existing auto rules the same way on load.
- Dictionary rows show `Heard as "…"` for auto entries.
- The user's stray `Pastack` entry was deleted; `stack → pstack` became the word `pstack` heard as "Paystack".

## Verification

Release build installed. Dictated via `say` into TextEdit (output mute temporarily off), then rewrote "latest" in three steps 2 s apart ("lat", "latte", "lattest"). No entry at 3.5 s and at 2.5 s after the last edit; one entry `lattest` (heard as "latest", no misspelling) 7 s after the last edit. Dictionary pane shows the `Heard as` line. Test entry removed afterwards; 193 package tests pass.
