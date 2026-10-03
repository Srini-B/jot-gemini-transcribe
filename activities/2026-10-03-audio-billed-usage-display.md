# Cost and History show what each call was billed on

2026-10-03. Released in 0.5.12 (37).

## Why

History showed every transcription as "in 0 · out 0". On the MacBook, every
`scribe_v2`, `gpt-transcribe`, `whisper-1` and MAI Transcribe 2 row had zero
tokens (257 Scribe calls, $0.67). These models charge by audio length and
report no tokens, so the ledger kept only the cost. The user asked for each
call to show its real billing unit: tokens for token-priced models and audio
length for audio-priced ones.

## What changed

- `TokenUsage.audioSeconds` and `UsageRecord.audioSeconds` hold the billed
  audio length. Migration `v2-audioSeconds` adds a nullable column to
  `usage.sqlite`.
- `TokenUsage.fromAudioMinutes` sets the length. This covers ElevenLabs and
  OpenAI's duration-billed models. The gateways report only the charge for MAI
  and `openai/gpt-transcribe`. For those calls, `UsageMeter.audioSeconds` (a
  task-local) carries the length of the audio sent.
  `GeminiTranscriptionService.sendTranscribe` and MAI meeting windows set it.
  `UsageMeter.record` uses it only for calls that report no tokens.
- `UsageFormat` (VoiceIQCore) writes the measure: "in 6932 · out 49",
  "22s of audio", or "billed by audio length" for older audio rows. It also
  holds the token formatter that the Mac and iPhone Cost screens each had.
- The History detail, Cost recent calls (Mac and iPhone) and iPhone breakdown
  rows use it. The Mac's detailed breakdown tables gained an Audio column, and
  they show "—" when a row has no value.

## Verification

- `scripts/test.sh`: 148 tests pass. `scripts/build-ios.sh`: builds.
- `scripts/release.sh` built a signed, notarized build, and it was installed in
  `/Applications` on the Mac mini. The migration ran on the Mac mini's real
  `usage.sqlite`, and `grdb_migrations` lists `v2-audioSeconds`.
- A copy of a 21.7 s MacBook recording was retried from History with MAI
  Transcribe 2 through the gateway. The transcription row was booked with
  `audioSeconds = 21.689375` and $0.00061, which is $0.10 an hour. History
  showed "microsoft/mai-transcribe-2 · 22s of audio · $0.0006" and
  "gemini-3.8-flash · in 6932 · out 49 · $0.0054". Cost → MAI → Detailed showed
  Audio 22s for Dictation, and the older meeting calls showed "billed by audio
  length".
- Restored afterwards: the test dictation and its recording were removed, and
  `transcriptionSource` and the Detailed toggle were returned to their earlier
  values. The two usage rows from the test stay in the ledger.

## Known gap

Audio rows booked before this change have no length. A backfill from cost was
not done: Scribe's cost includes the keyterm add-on when dictionary terms were
sent, so the length cannot be recovered exactly.
