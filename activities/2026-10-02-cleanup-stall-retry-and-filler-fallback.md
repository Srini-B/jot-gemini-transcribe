# 2026-10-02: Fresh-connection cleanup retry, filler fallback, persisted failure reasons

## Incident

Two MacBook dictations on 0.5.11 were pasted with every "uh" intact. Both used
MAI Transcribe 2 for transcription and gpt-6-luna (OpenAI direct) for cleanup:

- 11:52:35 IST, session `95EFA4B1` (5.6 s of audio): "Do not check on main branch, check on, uh, development branch. …"
- 12:06:45 IST, session `5E520F11` (48 s of audio): "Yeah, let's do that. And uh, I would also like you to uh, research uh, …" (16 fillers)

Evidence:

- In `history.sqlite`, `rawTranscript == cleanedTranscript` for both sessions. Pipelines took 16.5 s and 18.9 s; other dictations that day took 2.5–5.7 s.
- In `usage.sqlite`, each session has only a `transcribe:microsoft/mai-transcribe-2` row. Every other recent dictation also has `cleanup:gpt-6-luna`.
- CFNetwork logs:
  - The MAI upload returned 200 in 2.1 s and 3.2 s.
  - The OpenAI cleanup request was fully sent (`request_duration_ms` 15 and 50), but no response headers arrived (`response_start_ms=0`, `response_bytes=0`). It failed with `-1001` at exactly the cleanup deadline: 14.2 s and 15.2 s. That is `cleanupDeadline` plus 2 s for the screenshot.
  - The first request reused a connection that had been idle for 134 s. The second ran on a fresh HTTP/3 connection whose 32 ms handshake had just succeeded.
  - `client:data_stall` at about 3.4 s also appears on successful requests whose server takes more than about 3 s, so it is not evidence of a dead connection.
- The code then inserted the raw transcript.

See the root-cause section below for why no code change explains the misses. The fillers come from MAI Transcribe 2. It writes every hesitation it hears, and the gateways expose no clean or verbatim option. The writing model never saw these transcripts, so it did not accept the fillers. The app's own "cleanup unavailable" line was logged at info level, which the unified log does not keep. Earlier cleanup misses of the same shape are on 09-27 and 09-28.

## Change

- `GeminiClient.cleanupWithFreshRetry` (`GeminiClient+FreshRetry.swift`):
  - The writing-rules call starts a second attempt after 45% of its deadline (clamped to 5–20 s) without an answer, or immediately on a timeout, network, or offline failure.
  - The second attempt runs on a new ephemeral `URLSession`, selected through the `GeminiClient.freshConnection` task-local inside `post`. It gets the remaining budget, at least 8 s. The first success wins and cancels the other attempt.
  - Auth, model, bad-request, and quota errors are not retried.
- `FillerStripper` (`FormattingPipeline/FillerStripper.swift`):
  - Removes standalone uh/um/uhm/erm/äh/ähm/euh, including the commas around them, and capitalizes a word that becomes a sentence start.
  - Runs only when cleanup failed or was rejected, and only for transcripts that keep fillers (MAI, ElevenLabs verbatim, Gemini verbatim or legacy, OpenAI transcription).
  - "er", "ah", "eh", and "hmm" stay because they are words in some languages. Quoted fillers stay too.
- The cleanup stage moved to `GeminiTranscriptionService+Cleanup.swift`. A failed or rejected cleanup now logs one error-level line, such as "Writing rules skipped: cleanup timed out; filler words removed". `TranscriptionResult.cleanupNote` carries the same reason into `SessionMeta.errorMessage`, which History shows as Details. The live path, the retry queue, and the recovery scanner all set it.
- `call <stage> via <endpoint> … took N ms` is now logged at notice level, so it persists.

## Verification

- Probed on the Mac mini with `URLSessionTaskMetrics` against `api.openai.com`. A request forced onto HTTP/3 in session A was followed by a request from a new ephemeral session B, which opened a new HTTP/2 connection (`reused=false`).
- Ran a temporary XCTest harness against a local server that never answers the first request. The second attempt opened a new client connection and returned the cleaned text after 5.4 s with a 12 s deadline. Other cases covered:
  - fast success skips the retry
  - `.offline` retries at once
  - `.auth` does not retry
  - both attempts failing throws
  - the first attempt still wins after the retry fails
  - a 503 cleanup falls back to the filler-stripped text with a note
- Ran `FillerStripper` on both incident transcripts and on English, German, and French edge cases. "Uhura", "umbrella", "hum", German "er", and quoted "um" are untouched.
- The `swift test` suite ran 133 tests with 0 failures. The harness was deleted after the run.

## Root cause investigation (same day)

No change between v0.5.10 and 0.5.11 (`759ebc2`) touches the batch cleanup request:

- `GeminiClient.post`, `openAIChat`, and the session configuration (unchanged since `033c708`, 2026-09-26) are the same.
- `cleanupDeadline` and `TimeoutPolicy` are unchanged, apart from deleting the live-only `liveFinal`.
- The screenshot budget and sequencing are unchanged.
- The diff removes only the live-path `polish` and adds the MAI branch in `sendTranscribe`.

Other evidence:

- The 0.5.11 process ran a successful ElevenLabs + gpt-6-luna dictation at 11:08 IST.
- Every OpenAI cleanup since the morning ran over HTTP/3, before and after MAI.
- A probe on the MacBook over the app's URLSession configuration reused or replaced an idle api.openai.com HTTP/3 connection after 30, 60, 134 and 134 s without a stall.
- Replaying the incident prompts, with fillers and without, through gemini-3.8-flash gave 1.3–5.4 s and zero thinking tokens, so the filler-heavy MAI text does not slow the model.

The two misses fall in one 15-minute window (06:22–06:37 UTC). Two Gemini cleanups after the provider switch (06:44, 07:07 UTC) were also slow (14.6 s and 9.2 s), but their usage rows show 3,200 and 1,642 thinking tokens, so they have a separate, model-side explanation.

The 09-27 and 09-28 misses happened on a different route (OpenRouter → google/gemini-3.8-flash) before MAI existed. Conclusion: the misses were external server-side non-responses, not a code regression. OpenAI usage for 06:22:43 and 06:37:37 UTC would show whether those requests were processed.
