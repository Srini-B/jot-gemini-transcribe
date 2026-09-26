# 2026-09-26: Meeting recording becomes an offer, ⌥M toggle, live preview, AI-destination prompt

## Why

- A Google Meet call in Chrome was recorded as two meetings. `CallDetector`
  reads whether the browser is capturing the mic; Meet's mute button drops that
  signal, so three misses stopped the recording and the next unmute started a
  new one. Auto start was also not wanted: the user should decide.
- Dictations into Amp came out as paragraphs. The cleanup pass did run
  (`pipelineSeconds` ≈ 3 s, punctuation changed), and the raw transcript
  already arrived as paragraphs. Both `PromptV1.rules` and the seed rules say
  lists only for clearly announced enumerations, and the dictation had none.
  The user's own rules (§20 "AI prompt mode") allow numbering distinct
  requests when the destination is an AI system, but the model had no signal
  that Amp is one: its bundle ID mapped to `.neutral`.

## What changed

- `MeetingEngine.detected(_:)` never starts or stops a recording. Idle →
  `callDetected` raises `onCallDetected`; the call disappearing while
  unaccepted returns to idle and raises `onCallEnded`.
- New `MeetingHUDController` shows `PillState.meetingPrompt` with a Start
  button and dismiss (30 s auto-dismiss, deferred while dictating).
- New `ShortcutAction.meetingToggle`, default ⌥M, recorder row in Settings →
  Dictation. `MeetingEngine.toggleRecording()` starts or stops; stop runs
  transcription plus summary and saves.
- `MeetingLivePreview`: `MicTap` and `SystemAudioTap` expose `pcmSink`; a
  `LaneMixer` sums both lanes and streams them through rolling VERBATIM
  `LiveTranscriptionSession`s (rotated every 540 s under the 10-minute server
  cap). `PillState.meetingRecording(since:)` shows the clock and the tail of
  the transcript.
- `PromptV1.ToneCategory.aiAssistant` for `com.ampcode.amp.macos`,
  `com.anthropic.claudefordesktop` (moved from `.code`), `com.openai.chat`,
  `com.openai.codex`, `ai.perplexity.mac`. The block numbers several distinct
  requests one per item, forbids invented lead-ins, and keeps a single request
  as prose.

## Verification

- Prompt: replayed the real 1537-character Amp dictation through
  `PromptV1.cleanupPrompt` + `gemini-3.8-flash` with curl. Baseline reproduced
  the app's paragraphs. With the `aiAssistant` block the two preface paragraphs
  stayed prose and the three requests became a numbered list (2.7 s). A
  single-request dictation stayed prose. A first draft of the block made the
  model add "Here is what needs to be changed:"; the final wording forbids
  invented lead-ins and that stopped. Splitting rules into `system_instruction`
  changed nothing measurable, so the single-message layout stays.
- `./scripts/build.sh` clean; `swift test` 209 tests, 9 skipped, 0 failures.
- Release build notarized and installed; ⌥M start/stop, the offer pill, and the
  Settings row exercised on the installed app (see the thread screenshots).

## Rollback

Revert the commit. Meetings recorded under the new flow keep their folder
layout; no migration.
