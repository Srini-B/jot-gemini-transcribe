# 2026-09-30: Mic that never starts, focused-field guard, live checks

## Why

- The owner sees "Mic didn't start" at the end of a dictation, more on the Mac
  than the iPhone, with a flat wave the whole time; the next try works. A long
  dictation lost that way is the worst outcome, so the failure has to be fixed
  or at least reported at the start.
- The owner asked for Parrot's focused-field check, keeping the existing rule
  that a result never pastes into a different app.
- iPhone silence trimming was asked for; it already applies there (below).

## Root cause

`completeFinalize` reports `.noAudio` when a recording wrote zero frames, and
that only happens at key-up. The engine gives no error in this case:
`engine.start()` succeeds and the tap never runs. Reproduced on the Mac mini
with a harness around `AudioCaptureEngine` by restarting coreaudiod 3 s before
`start()`. 2 of 8 takes recorded zero frames. The logged one had been built
while the device was coming back (44.1 kHz/2 ch); the rebuild a second later
read 48 kHz/8 ch and delivered at once. Restarting coreaudiod stands in for
what sleep and wake, Bluetooth renegotiation, or another app changing the
device format do; which of those hits the owner is not known. Sample-rate
changes and default-input flips on the MacBook did not reproduce it.

## What changed

- `AudioCaptureEngine` first-buffer watchdog, shared by both apps: no buffer
  1 s after start (3 s on Bluetooth) rebuilds the graph once and tells the user
  "Mic restarted — say that again"; still nothing after the rebuild fires
  `onEngineDied(noAudioMessage)`, and the coordinator fails the take as
  `.noAudio` right away. `stop()` disarms it.
- `start()` skips a prewarmed spare whose tap format no longer matches the
  device's current one (`AudioDeviceQuery.inputFormat(of:)`).
- `AudioDeviceQuery` moved to its own file.
- Focused-field guard (Mac): `DictationContext.focusedField` is filled off the
  main thread at session start with the target app's focused element if its
  text can be set; `AXInserter.insert` sends the result to the clipboard with
  the chip when a different field of the same app has focus. An empty capture
  compares nothing (Parrot's rule for Chromium and Electron).
- Silence trimming on iOS: nothing to do. The iPhone app uses the same
  `GeminiTranscriptionService` and `AudioCaptureEngine` (16 kHz Int16 CAF), so
  yesterday's `AudioChunker.speechRange` already applies to it.

## Verification

- Watchdog, harness on the Mac mini: the take whose graph was built at
  44.1 kHz/2 ch logged "no audio 1.0s after start … rebuilding", then the
  first buffer, and kept 1.9 s of its 3 s instead of none. Warm starts are
  still used on the Mac mini's virtual mic and the MacBook's built-in mic;
  the format check fell back to a fresh graph only when the rate really
  changed.
- Coordinator, throwaway XCTest (deleted): a fake engine firing
  `onEngineDied(noAudioMessage)` two seconds into a hands-free take ended as
  `.failed(.noAudio)` with no "dictating what was captured" hint.
- Spacing and trimming end to end with the real Gemini key: two MacBook
  recordings with 8.6 s and 7.2 s of silence at the edges went through
  `GeminiTranscriptionService` on the one-call path and the two-call path.
  16.2 s and 60.6 s were sent (24.9 s and 67.8 s recorded), and every sentence
  of the saved transcripts came back.
- Writing rules on `gemini-3.8-flash` (the gap from 2026-09-29): 18 fixtures,
  2 runs each, 1.1 to 3.1 s per call. Emails laid out with greeting, blank
  lines, sign-off and name in 10 of 10 runs; greeting-plus-one-line messages
  inline in 8 of 8; sentence lists with blank lines between items; short-item
  lists tight; self-correction, question, injection and spoken punctuation
  right; the validation gate accepted all 36 answers. Gemini, unlike Luna,
  kept "We need to pick up:" above the grocery list.
- `scripts/test.sh`: 192 tests, 9 skipped, 0 failures. `scripts/build-ios.sh`
  succeeds. `scripts/build.sh` succeeds; one run failed in the "Sign Sparkle
  helpers" phase on a stale Debug product and passed after removing it.
- Not verified: the focused-field guard in a running app. No process here
  holds Accessibility permission except cua-driver and the installed app on
  the MacBook, which was not replaced. The Mac check to run: start a
  dictation in one field of an app, click another field of the same app
  before it finishes, and expect "Copied — press ⌘V"; stay in the field and
  expect a normal paste, in Chrome and Slack as well as TextEdit.
