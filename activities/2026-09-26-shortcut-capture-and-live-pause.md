# 2026-09-26: Shortcut capture guard, live-mode pause that heals, small UI fixes

## Why

Recording a new shortcut in Settings fired the old ones. The dictation key was
right Option; pressing it to start a combo for the meeting shortcut began a
dictation, and Option-M then started a meeting recording. Both taps
(`EventTapEngine`, `GlobalShortcutEngine`) run on their own threads and never
knew a Settings row was listening. The row also had no cancel control, and
Reset did not end the recording state.

Settings → Dictation showed "Used live for 19 of the last 25 dictations (76%).
Most fell back because the transcript did not arrive in time." The defaults on
this Mac read `liveFallback_noFinal = 7`, `liveConsecutiveFailures = 3`. Two of
those were today's silent test dictations (8.9 s and 6.9 s, both `failed /
empty` in history): an empty final transcript was classified as `noFinal`.
Three failures in a row set `shouldStopTrying`, and `makeLiveSession` then
skipped live on every dictation. The success that would clear the streak could
never happen, so live mode stayed off until the toggle was flipped. The other
`noFinal` counts line up with the history rows whose `pipelineSeconds` sit at
12.9–18.8 s (fallback upload after the 6 s final deadline), which is network or
server latency, not a broken feature.

## What changed

- `HotkeyEngine/ShortcutCapture`: process-wide flag with an owner ID. Both
  taps pass key events through while it is set. Beginning a capture posts
  `voiceIQShortcutCaptureDidBegin` so the other rows stop listening. Rows show
  an `xmark.circle` cancel while recording; Reset and leaving the pane end the
  capture.
- `LiveOutcome.silent` for an empty final transcript; `LiveTranscriber` does
  not count it. `LiveStats.classify` no longer maps "empty" to `noFinal`.
- `LiveStats.shouldStopTrying` now expires `retryAfter` (10 min) after the
  last failure, so one attempt runs and a success clears the streak. The
  footer says "Paused after N failures in a row; tries again in M min."
- Permission rows use the outlined `checkmark.circle` in secondary color when
  granted and `xmark.circle.fill` in the error color when not, matching the
  API key badge.
- Meetings list divider reaches the titlebar (same rectangle trick as the main
  sidebar). About pane shows the wordmark spelling "VoiceiQ".

## Verification

- `swift test --package-path VoiceIQCore`: 209 tests, 9 skipped, 0 failures. `testEmptyFinalIsUnusable` became `testEmptyFinalIsSilentNotAFailure`.
- Recorder rows driven through the AX API (`.amp/in/axpress`): arming the
  Meeting row shows the cancel icon; arming Translate stops the Meeting row;
  Cancel and Reset both end the recording and Reset restores ⌥M.
- Synthetic ⌥K and ⇧M reached the row's local monitor and were recorded while
  the guard was set. Synthetic ⌥M did not reach the window at all, even with
  both taps down, so another process on this Mac claims ⌥M when Voice IQ does
  not consume it first. Not an app bug; noted for the user.
- Release build notarized and installed; guard re-checked there: with a row
  armed, right Option started no dictation and ⌥M started no meeting.
