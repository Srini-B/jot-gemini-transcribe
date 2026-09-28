# OpenAI dictation: a second transcript for the writing model

2026-09-28, late evening. Not committed or released yet.

## Why

A MacBook dictation at 8:48 PM on OpenAI said "The rest of the other things look
fine to me". `gpt-transcribe` heard "But stop the other things. Look, find to
me.", and GPT-6 Luna, which only sees text, kept the first half and dropped the
second. On Gemini this is repaired because the flash model hears the recording.
The user asked to try sending the audio to Luna first, and to use a second
transcript if that failed.

## Luna cannot take audio

Probed with the real key from the Mac mini:

- Chat Completions with `input_audio` (wav): 400, "Content blocks are expected
  to be either text or image_url type".
- Responses API with `input_audio`: "Audio input is not available". `input_file`
  with audio/wav is refused too.

The comment in `GeminiClient+OpenAI.swift` that said Luna takes wav/mp3
`input_audio` was wrong and is corrected. `writingModelHearsAudio` stays
Gemini-only.

## What changed

- `GeminiClient.secondOpinionTranscript` sends the dictation FLAC to `whisper-1`
  (`OpenAIConfig.secondOpinionModel`) on the OpenAI direct route only.
- `GeminiTranscriptionService.transcribe` starts it in parallel with the primary
  transcription for single-chunk dictations with writing rules on. Once RAW is
  in, `awaitSecondOpinion` waits at most `min(5, max(1.5, 0.04 × seconds))`,
  then drops a late, failed, empty or identical SECOND.
- `PromptV1.cleanupPrompt(secondTranscript:)` appends the SECOND rule after the
  layout reminder and puts `SECOND: …` before `RAW: …`. The rule keeps RAW by
  default and takes SECOND's words only for a stretch of RAW that makes no sense.
- `openAIMessages` splits at `SECOND:` when screenshots are attached, so both
  transcripts stay in the user message.
- `PriceBook`: `whisper-1` at $0.006/min (OpenAI pricing page). whisper-1
  returns `usage.duration`, so it is booked like `gpt-transcribe`.
- Gemini, the gateways, live transcription (`polish`) and multi-chunk recordings
  are unchanged.

## Measurements (2026-09-28)

Prompt experiments with Python against the API, full production prompt:

| Case | With SECOND | Without |
| --- | --- | --- |
| 8:48 PM text, whisper's reading as SECOND | fixed 14 of 14 | kept "But stop the other things" 4 of 4 |
| Synthetic RAW with 5 mishearings, real whisper-1 SECOND | fixed 8 of 8 | – |
| Correct RAW, whisper-1 with "three tires" and "Um" | RAW kept 8 of 8 | – |

Through the app's Swift client, after implementation (throwaway test, deleted):

- 8:48 PM case: "But the rest of the other things looked fine to me." Gate passed.
- Correct RAW against "three tires": kept "three tiers", no "Um". Gate passed.
- Synthetic mishearings: "Czech", "lunch" and "data" were repaired; "Maria"
  stayed "Maria" because both names make sense, which is what the rule says.
- Timing, SECOND running beside RAW: 21 s clip RAW 2.6 s, SECOND ready 3.3 s;
  84 s clip RAW 3.6 s, SECOND ready 5.2 s.
- Earlier standalone timings: whisper-1 1.4–2.3 s (21 s) and 5.8–6.1 s (84 s);
  gpt-transcribe 2.3–2.9 s and 3.1 s.

Cost: +$0.006 per minute of dictation on OpenAI with writing rules on.

## Verification

- `./scripts/test.sh`: 192 tests, 9 skipped, 0 failures.
- `./scripts/build.sh` (Mac Debug) and the iOS simulator build: succeeded.
- Not verified: a dictation through the full app on a device, and the user's
  real 8:48 PM recording (MacBook offline, earlier local copy deleted).

## Rollback

Return nil from `secondOpinionTranscript`. With no SECOND, the prompt and the
message layout are exactly what they were before this change.
