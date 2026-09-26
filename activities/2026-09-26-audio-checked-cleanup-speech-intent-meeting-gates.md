# 2026-09-26: Audio-checked cleanup, speech-based intent, meeting silence gate

## Why

- The 1:53 PM dictation was pasted with the wrong meaning. Listening to the
  recording: the user said "have a look at it tomorrow. We will connect first
  thing on Monday". The live model (`gemini-3.5-transcribe-live`) returned
  "I will look at it. Tomorrow we will connect our first thing on Monday". The
  cleanup pass saw only that text and could not recover the sentence boundary.
  Batch `gemini-3.5-transcribe` on the same audio was correct (6 s). Cleanup
  with the FLAC recording attached fixed every error in 3.1 s (1.7 s without).
  Removing the live preview alone would not fix this: live text is the input
  to cleanup either way. Audio makes cleanup authoritative.
- Silent dictations showed a dictionary word in the pill. The live model is
  biased with `customVocabulary`, and on silence it emits one of those words.
- The user rejected app-based tone classification. `PromptV1.ToneCategory`
  mapped the frontmost bundle ID to an email / work chat / personal chat /
  code / neutral block (and, from the previous entry, an AI-assistant block).
  Intent must come from the speech.
- A 12 s meeting of fan noise produced a Chinese one-word transcript ("哇。"),
  a Chinese summary, and no title. The diarizing model hallucinates on silence.
- Meetings list rows showed no time; the pill said "Making meeting notes…"
  after stop; a "View" label sat before the Notes/Transcript picker.

## What changed

- `PromptV1.cleanupPrompt(audioAttached:)`, `GeminiClient.cleanup(audioFLAC:)`,
  `TranscriptionServicing.polish(_:context:audioURL:)`. The coordinator passes
  the session `audio.caf`; the service FLAC-encodes it (cap 12 MB) and the
  deadline grows by bytes/400 000 s. `docs/PRIVACY.md` now says the audio is
  sent with the writing-rules request.
- `DictationCoordinator.speechHeard` gates live partials until the level
  reaches `trailingSpeechThreshold` (0.08) once in the session.
- `ToneCategory` and every `tone:` parameter removed. The last bullet of
  `PromptV1.rules` asks the model to infer destination and shape from speech.
  Ask Anything matches the register of the instruction and selection.
  Verified by prompt replay: an Amp dictation with several requests becomes a
  numbered list with no invented lead-in; WhatsApp and prose dictations stay prose.
- `AudioMixer.speechStats(url:)` (100 ms RMS windows). `hasSpeech` needs 2 s
  above −42 dBFS and a 6 dB 10th–90th percentile spread. Measured on
  `mixed.caf` files: fan noise 0.3 s / 3.5 dB, a 77 s call 50 s / 17 dB, a
  99 s dictation 32 s / 12 dB. `MeetingEngine.process` saves "No speech
  recorded" notes without any model call when the gate fails, and skips the
  summary when the transcript has fewer than 8 words.
- `MeetingsView` rows show start–end time; the picker label is hidden.
  `MeetingHUDController` shows the dictation processing wave after stop.
- `ScreenContextCollector` logs each capture (bytes, kept count) so the
  `screen` log category shows whether screenshots happen.

## Meeting start froze the app

Starting a ⌥M meeting on the release build hung the main thread: `sample`
showed `MeetingEngine.startRecording → MicTap.start → control.sync →
AudioDeviceStart` waiting on a CoreAudio mutex while coreaudiod logged
`HALS_IOContext_Legacy_Impl::StartIOThread: got an error from starting the
IO thread, Error: 0x3C` every 14 s. Every later shortcut press queued behind
it, which is the "app froze, tray menu would not open" symptom.

A standalone binary (`.amp/in/mictest4.swift`) reproduced it: process tap +
aggregate device started first, then `AudioDeviceStart` on the built-in mic
hung in 4 of 7 runs (one run returned after 9.4 s). Mic first, then the tap:
40 ms in every run, and the tap still delivered 203 callbacks in 3 s while
`say` played. `MeetingEngine.startRecording` now starts the mic before the
system tap. Every earlier successful meeting today happened to win the race.

## Checked against FluidVoice

FluidVoice's `MeetingAutoDetector` is "prompt-only: it never starts or stops
a recording itself"; capture is a separate continuous session stopped by the
user, and 60 s without meeting evidence only shows a still-recording nudge.
Our `MeetingEngine.detected(_:)` has the same shape since the previous entry:
mute cannot split a meeting because detection never touches a running
recording.

## Verification

- `swift test --package-path VoiceIQCore`: 209 tests, 9 skipped, 0 failures.
- `./scripts/build.sh` clean.
- Runtime checks after release build: see the thread reply for the silent
  dictation, silent ⌥M meeting, spoken ⌥M meeting, and screen-context log.
