# 2026-09-27 — A 12-minute dictation stuck on "still offline"

## Incident

A 714 s dictation at 06:40 IST failed with "Rate limited". Retry from History
answered "Still offline — will retry automatically when you're back" on a
machine that was online. The audio was intact (`audio.caf`, 22.8 MB).

## Cause (measured)

The key is on Gemini Tier 1, where `gemini-3.5-transcribe` is metered at
10 000 input tokens per minute. Audio bills at ~25 tokens/s, so one ten-minute
chunk is ~15 000 tokens. The first request of the minute is accepted anyway;
the second chunk (~2 900 tokens) is refused with HTTP 429 and `Retry-After`
between 22 s and 60 s. Reproduced with two direct `POST /v1beta/interactions`
calls on the same audio.

Three things then compounded it:

- `GeminiClient.post` only honoured a `Retry-After` of 8 s or less, so the
  throttle surfaced as `.rateLimitedTransient` and the session failed.
- Every retry re-sent chunk 0 first ($0.04 each, three times) which drained
  the minute's budget again, so chunk 1 could never succeed.
- `RetryQueue` mapped `.rateLimitedTransient` to `.stillOffline`, and the only
  drain triggers were launch and a network-path change, so "History will retry
  it shortly" was never true and the manual Retry copy talked about being
  offline.

## Change

- `TranscriptionError.rateLimitedTransient` now carries the server's
  `retryAfter`, and the 429 body is logged (message private).
- `GeminiTranscriptionService.transcribeWithRetry` waits the named delay once
  (cap `TimeoutPolicy.rateLimitWait` = 65 s) before resending a transcribe
  request. Cleanup and Ask Anything keep the old ≤8 s wait.
- Multi-chunk uploads write each finished chunk's text to `chunks.json`
  (`ChunkTranscripts`, keyed by frame range) beside the audio; a retry sends
  only the missing chunks and deletes the file when all are in.
- `RetryQueue` has a `.rateLimited(retryIn:)` outcome and `scheduleDrain(after:)`.
  A throttled drain or manual retry re-drains after `Retry-After` + 2 s; a
  live session that fails on `.rateLimited` schedules a drain after 65 s.
  Pill copy for a throttled manual retry: "Gemini is rate limited — retrying in Ns".
- A recovered row now clears its stale `errorCode`/`errorMessage`.

## Verification

Release build installed. At launch the queue drained the failed row: chunk 0
sent and cached, chunk 1 got 429 (`retryAfter=22`), waited, got 429 again
(`retryAfter=58`), queue scheduled a drain in 60 s. That drain logged
"2 chunks, 1 already transcribed", sent only chunk 1 (3 584 input tokens),
ran cleanup, and the row is `recovered` with a 4 781-character raw transcript.
`chunks.json` was removed. `swift test`: 193 tests, 0 failures.

The Cost pane shows $0.1414 for that dictation; $0.124 of it is the three
pre-fix re-sends of chunk 0.
