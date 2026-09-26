# 2026-09-26: Dictation key becomes a single-press toggle

## Why

The user wants one gesture only: press the dictation key to start hands-free,
press it again to stop. Hold-to-talk, double-tap to lock, and Space while
holding were never used and made a firm tap ambiguous.

## What changed

`HotkeyProcessor` has two phases, idle and locked. A press while idle emits
`.begin` and `.lockIn`; the next press emits `.finalize`; a release never does
anything; Esc cancels; another key within 1 s of the press is an accidental
chord and cancels silently. Removed with it: the 0.3 s hold threshold, the
double-tap window and its timer in `EventTapEngine`, the Space-lock keyDown
branch, the `shortTapHint` intent and coaching tip, the `doubleTapLock` setting
and its toggle in Settings → Dictation, and the debug URL parameter.

`DictationController` treats a refused `.begin` as the stop when a session the
pill or menu started is recording, so the key still ends every kind of session.
`handleAccidentalChord` no longer finalizes a locked session; the grammar only
reports a chord within a second of its own press, so the session is young and
cancelling loses nothing.

Copy updated: the Settings row reads "Press to start and stop", the menu-bar
status reads "Ready — press … to dictate", onboarding teaches two gestures, and
the empty History screen names the configured key.

Ask Anything and Translate keep their own shortcuts' hold-or-tap behaviour;
the request was limited to the dictation key.

## Verification

- `swift test --package-path VoiceIQCore`: 193 tests, 9 skipped, 0 failures.
  `HotkeyProcessorTests` rewritten for the toggle grammar (press starts and
  next press stops, long hold does not stop, Esc cancels, chord inside and at
  the 1 s boundary, reset, idle ignores). The two coordinator tests that
  asserted a short tap or chord finalizes a hands-free session were replaced by
  one that asserts a chord cancels the young session and one that a stray begin
  during transcription is refused without cancelling it.
- `./scripts/build.sh` clean; release build installed to `/Applications/Voice IQ.app`.
- Live check with the installed app, driving right Option with a synthetic
  CGEvent: the first press started a session and opened the pill, the second
  press finalized it after 8.9 s and a history row appeared. That row failed
  the audio gate (`tooNoisy`, speech peak -43 dBFS over a -50 dBFS floor)
  because the test speech came from the speakers, not a person, so the
  transcription path was not exercised by this check.

## Also checked

The dictation that carried this request (17:25 IST, 40.6 s, live + audio
cleanup, 4.7 s pipeline) was compared against a verbatim batch transcription of
its recording. Every word matched. The cleanup dropped the openers "So", "And",
and "So", hyphenated "double-press", "single-press", and "hands-free", and put
the opening question in its own paragraph. No list was made, which is right
for one question plus one request.
