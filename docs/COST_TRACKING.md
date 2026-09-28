# Cost tracking

VoiceiQ meters every model call, Gemini and OpenAI, and shows the result under
Settings → Cost Analysis (`voiceiq://settings/cost`) and per dictation in
History.

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

`GeminiClient.post` is the only REST transport for every provider and gateway,
so it is the one place that reads usage on a 200. On Google's endpoint two
envelopes are handled by `TokenUsage`:

- `:generateContent` → `usageMetadata` (`promptTokensDetails`,
  `candidatesTokensDetails`, `thoughtsTokenCount`, `cachedContentTokenCount`).
- `v1beta/interactions` → `usage`. `total_output_tokens` came back 0 while
  `model_invocation_token_counts` carried the real output count (probed
  2026-09-26), so the per-invocation list is authoritative.

The live socket (`LiveTranscriptionSession`) reads `usageMetadata` frames as
they arrive and books the largest total at `finish()`. If no frame carried
usage, it estimates: audio seconds × 25 tokens/s for the transcribe models
(32 for other models) and output characters ÷ 4, flagged `isEstimated`.

On OpenAI's own API, the transcription models (`gpt-transcribe`,
`gpt-4o-transcribe`) bill per audio minute and report
`usage: {type: "duration", seconds}`; `TokenUsage.fromOpenAIDuration` books
`seconds / 60 × PriceBook.perMinutePrice` as `reportedCostUSD` with no token
counts. The realtime socket (`OpenAILiveDialect`) books the seconds it sent
at the `gpt-live-transcribe` rate. Chat models (GPT-6 Luna, and
`gpt-4o-transcribe-diarize`, which bills tokens) use the OpenAI-shaped
`usage` block (`TokenUsage.fromOpenAI`).

## Attribution

`UsageMeter.scope` is a task-local `UsageScope(activity, sessionID)`. It is set
around the dictation finalize task in `DictationCoordinator`, the retry queue's
transcribe, and `MeetingEngine` processing.
Calls without a scope are booked as `other`.

## Pricing

`PriceBook` holds paid-tier Standard prices per million tokens from
ai.google.dev/gemini-api/docs/pricing (copied 2026-09-26) and Standard prices
from developers.openai.com/api/docs/pricing (copied 2026-09-28; GPT-6 Luna,
GPT-6 Sol, `gpt-4o-transcribe-diarize`, plus the per-minute table for the
transcription models), matched by the longest model-ID prefix with any
`google/` or `openai/` gateway prefix removed. Gemini 3.8 Flash doubles on 2027-01-01 and the book
switches on that date. Models without an entry are stored with `costUSD = nil`
and shown as unpriced; totals that include an unpriced or estimated call show
a ≈ prefix.

The app cannot tell whether a Gemini key is on the free tier, so it always
shows the paid-tier figure.

Calls served by a gateway (`SettingsStore.activeRoute.gateway` is
`.openRouter` or `.vercel`, for either provider) report their charge in the
response: `usage.cost` on chat and
OpenRouter transcription calls (`TokenUsage.fromOpenAI`), and
`providerMetadata.gateway.cost` on Vercel's transcription protocol
(`TokenUsage.fromVercelTranscription`, which also reads the per-modality token
counts under `providerMetadata.google.usage`). `TokenUsage.reportedCostUSD`
carries it and `UsageRecord` stores it instead of the `PriceBook` figure. Those
rows show the gateway model label (`google/gemini-3.8-flash`,
`openai/gpt-6-luna`); `PriceBook` strips the prefix when a gateway response
carries no cost.

## UI

`CostPane` shows one provider at a time. It opens on the provider selected in
Settings → Advanced, and a Gemini/OpenAI toggle switches to the other; every
read filters `usage` rows by model ID (`ModelProvider.modelPrefixes`: `gemini`
and `google/` for Gemini, `gpt`, `whisper` and `openai/` for OpenAI). It shows
today, this week, this month, and all time totals; a period picker drives the
by-action and by-model tables and the recent-calls list. The footer names the
price source (`ModelRoute.pricingNote`): the active gateway for the selected
provider, the provider's pricing page for the other.
`HistoryPane` shows the summed session cost on each row and the detail sheet
lists each call with its model and token counts.
