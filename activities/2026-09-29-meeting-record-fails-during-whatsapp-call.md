# 2026-09-29: Meeting recording failed to start during a WhatsApp call

## Report

- MacBook, 16:44 and 16:46, during a WhatsApp call: the call offer's Record
  and Option-M both showed "Meeting recording failed". Each attempt left a
  meeting folder with an empty `mic.caf`, no `system.caf`, and status
  `recording`.

## Root cause

- A call app that turns on voice processing switches the built-in mic from 1
  input channel to 3 interleaved channels. `MicTap.attach` built its input
  format with `AVAudioFormat(streamDescription:)`, which returns nil for more
  than 2 channels without a channel layout, so `start()` threw
  `MicError.format` before any audio started.
- `MeetingEngine.fail` did not log the error, so the unified log had nothing.
  The failed start also left its folder behind as a "Recording" meeting.

## Change

- `MicTap.attach` gives a >2-channel stream a discrete channel layout and maps
  channel 0 into the mono converter. The default map for 3 channels is
  silence (`channelMap` `[-1]`).
- `MeetingEngine.fail` logs the error and deletes the folder it created.

## Verification

- Reproduced with a throwaway process that enables voice processing on the
  input node: the mic reported 3 channels and `AVAudioFormat` returned nil.
- With the change, the real `MicTap` recorded 3 s (47,952 frames at 16 kHz)
  while voice processing ran, and 3 s with it off.
- `scripts/test.sh`: 192 tests, 0 failures.
- Not verified: a real WhatsApp call. In voice-processing mode the raw channel
  measured about 30 dB quieter than the normal mic; `TrackAudio.gain` lifts
  quiet tracks by up to 32 dB, but transcript quality of the local speaker in a
  call is untested.
- The installed VoiceiQ (0.5.4) still has the bug until the next build.
