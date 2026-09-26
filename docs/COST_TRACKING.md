# Cost tracking

VoiceiQ meters every Gemini call and shows the result under Settings → Cost
Analysis (`voiceiq://settings/cost`) and per dictation in History.

## What is recorded

Each successful model call becomes one `UsageRecord` in
`~/Library/Application Support/VoiceiQ/usage.sqlite` (GRDB, WAL). Fields:
time, activity, stage, model, session ID, token counts by modality (text,
audio, image, cached in; text, audio, thought out), an `isEstimated` flag,
and `costUSD`.

Activities: `dictation`, `askAnything`, `translate`, `meeting`, `other`.
Stages: `liveTranscribe`, `transcribe`, `cleanup`, `answer`, `translate`,
`webQuery`, `meetingTranscribe`, `meetingSummary`.

The ledger is separate from `history.sqlite` so deleting a dictation or its
audio never changes what it cost.

## Where the counts come from

`GeminiClient.post` is the only REST transport, so it is the one place that
reads usage on a 200. Two envelopes are handled by `TokenUsage`:

- `:generateContent` → `usageMetadata` (`promptTokensDetails`,
  `candidatesTokensDetails`, `thoughtsTokenCount`, `cachedContentTokenCount`).
- `v1beta/interactions` → `usage`. `total_output_tokens` came back 0 while
  `model_invocation_token_counts` carried the real output count (probed
  2026-09-26), so the per-invocation list is authoritative.

The live socket (`LiveTranscriptionSession`) reads `usageMetadata` frames as
they arrive and books the largest total at `finish()`. If no frame carried
usage, it estimates: audio seconds × 25 tokens/s for the transcribe models
(32 for other models) and output characters ÷ 4, flagged `isEstimated`.

## Attribution

`UsageMeter.scope` is a task-local `UsageScope(activity, sessionID)`. It is set
around the dictation finalize task in `DictationCoordinator`, the retry queue's
transcribe, `MeetingEngine` processing, and the meeting live preview's start.
Calls without a scope are booked as `other`.

## Pricing

`PriceBook` holds paid-tier Standard prices per million tokens from
ai.google.dev/gemini-api/docs/pricing (copied 2026-09-26), matched by the
longest model-ID prefix. Gemini 3.8 Flash doubles on 2027-01-01 and the book
switches on that date. Models without an entry are stored with `costUSD = nil`
and shown as unpriced; totals that include an unpriced or estimated call show
a ≈ prefix.

The app cannot tell whether a key is on the free tier, so it always shows the
paid-tier figure.

## UI

`CostPane` shows today, this week, this month, and all time totals; a period
picker drives the by-action and by-model tables and the recent-calls list.
`HistoryPane` shows the summed session cost on each row and the detail sheet
lists each call with its model and token counts.
