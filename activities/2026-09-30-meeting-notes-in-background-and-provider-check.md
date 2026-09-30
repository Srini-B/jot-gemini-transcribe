# 2026-09-30: Meeting notes in the background, four-color wave, provider check

## Why

- The owner found the pill confusing after stopping a meeting: it showed the
  working wave and "Still working…" until the notes were saved, which suggests
  a new dictation or meeting would interfere. Notes now run in the background
  and the pill is free at once.
- The dictation wave was plain blue while the meeting wave was four-color. The
  owner wants the four colors everywhere.
- The owner judged the 2026-09-30 WhatsApp meeting's transcript and notes as
  poor: "EOD" came back as "U_D_", and the notes called the deadline unclear.

## What changed

- `MeetingPhase` lost `.processing`. `MeetingEngine.phase` is only the recorder
  (idle, offer, recording, failed start). Stopped, retried and regenerated
  meetings sit in `MeetingEngine.processing: Set<MeetingID>` while their
  transcript and notes are made, so several can run at once and a new
  recording can start straight away. `isBusy(_:)` guards Retry and Redo per
  meeting. A processing failure no longer touches `phase`.
- Mac pill: stop returns the pill to rest immediately; the green tick still
  shows when notes are saved, unless a dictation, meeting offer, answer or
  update prompt holds the pill. An update relaunch still waits for background
  notes (`isInUse`).
- iOS: the recorder card no longer shows "Writing notes"; the row's Processing
  chip already marks a meeting in progress.
- `WaveformView` colors bars with the four-color sweep in the listening state
  too, and in the Reduce Motion meter.

## Provider check on the 2026-09-30 meeting (6 min, WhatsApp)

The meeting ran on OpenAI (the selected provider): `gpt-4o-transcribe-diarize`
for the transcript and `gpt-6-luna` for the notes (usage.sqlite). The same
audio was rerun through each meeting route with the shipping
`MeetingTranscriber` and `meetingNotesJSON`:

| Route | Transcript around 1:27 | Notes |
| --- | --- | --- |
| OpenAI direct (as shipped) | "by L_E_O_D_ today", "by U_V_D_" | Deadline "today", acronyms flagged unclear |
| Gemini direct (`gemini-3.5-transcribe`, notes `gemini-3.8-flash`) | "by EOD today", "by the EOD", "By EOD?" | Missed the enable-and-send action in 2 of 2 runs |
| Gemini transcript + OpenAI notes (`gpt-6-luna`) | as Gemini | "Enable the unavailable options and send them", deadline "EOD today" |
| Gemini via OpenRouter | failed 2 of 2, `unreadable_segments` | none |
| Gemini via Vercel | failed, free tier has no `gemini-3.8-flash` | none |

The misheard acronym comes from the OpenAI diarizing model, which spells
letters out with underscores. Routing was not changed.

## Verification

- `scripts/build.sh` (macOS Debug) and `scripts/build-ios.sh` built.
- `scripts/test.sh` ran the VoiceIQCore suite.
