# ElevenLabs Scribe as a transcription source, and lifetime audio time

2026-09-28, night. Not committed or released. Built and checked on the Mac mini
while the user was away; no ElevenLabs key was available.

## Why

The user asked for ElevenLabs Scribe v2 (batch) and Scribe v2 Realtime (live)
as an optional transcription stage for either provider, with the transcript
then going to the provider's writing model (Gemini 3.8 Flash or GPT-6 Luna),
wired into both apps everywhere including the Cost page. They also asked for
total audio time next to words and WPM, because transcription is priced per
minute or per hour.

## Decisions made on the user's behalf

- **Picker placement.** Mac: Settings → Advanced, a "Transcription" segmented
  control (provider name / ElevenLabs) above the ElevenLabs key. iPhone:
  Settings › Provider & Keys (also the onboarding keys page), a Transcription
  group under the provider's key. The picker appears only once an ElevenLabs key
  is stored; without a key the provider transcribes regardless of the stored
  choice.
- **Mac onboarding unchanged.** It asks only for the provider key, as it already
  does for TinyFish. The iPhone's onboarding shares the Provider & Keys form, so
  it has the ElevenLabs card.
- **Audio goes only to ElevenLabs.** With ElevenLabs picked, the Gemini one-call
  path, the OpenAI `whisper-1` second transcript, and the audio attached to
  Gemini's cleanup of a live transcript are all skipped. The writing model sees
  text only.
- **Dictation only.** Meetings keep their diarizing providers.
- **Keyterms capped at 100** (batch). More than 100 makes ElevenLabs bill
  every request at least 20 s. Realtime allows 50.
- **`no_verbatim`** follows smart mode; `tag_audio_events=false` keeps
  "(laughter)" out of the text.
- **Live turns roll at 20–30 s** on ElevenLabs. The server auto-commits after
  about 36 s of uncommitted audio, which would give one turn two finals and
  break the session's one-final-per-turn accounting.
- **The live pill keeps earlier turns.** The partial stream now shows closed
  turns plus the open one on every dialect, instead of blanking at each roll.
- **Cost page gets a third tab**, ElevenLabs, priced at list price. Plan-included
  hours aren't subtracted.
- **Audio stat** counts the same dictations as the word count (those with a
  transcript). Deleted history drops out of it, as it does for words. Shown as
  "42 min" under an hour, then "3.2 h".

## What changed

- Core: `TranscriptionSource`, `ModelEndpoint.elevenLabs`, `KeychainStore`
  ElevenLabs key, `SettingsStore.transcriptionSource`,
  `GeminiClient+ElevenLabs.swift` (batch call, key check, keyterm rules,
  pricing), `ElevenLabsLiveDialect`, `WebSocketTransport.elevenLabs`,
  `LiveDialect.setupFrame` optional plus `activityRoll`, `CostSource` for the
  Cost filters, `PriceBook` Scribe prices, `HistoryStore.Stats.totalAudioSeconds`.
- Mac: `TranscriptionSourceSection` and `GatewayKeySection.elevenLabs`
  (Advanced), Cost toggle, Privacy recipients, failure copy names ElevenLabs,
  history header "of audio", live footer copy.
- iPhone: `KeySlot.elevenLabs` card and Transcription picker, Cost toggle,
  Privacy audio row, Home stats as a 2×2 grid with Audio, live footer copy.
- Docs: architecture (new ElevenLabs bullet), PRIVACY, COST_TRACKING, IOS.

## Sources

Official docs read 2026-09-28: elevenlabs.io/docs/api-reference/speech-to-text
(convert and realtime), /docs/overview/models, /docs/overview/capabilities/speech-to-text,
/docs/eleven-api/resources/errors, /pricing/api. The keyterm wire encoding
(repeated fields and query parameters), the empty-audio commit and the absence
of a setup message come from the official elevenlabs-js and elevenlabs-python
SDK sources.

Pricing: Scribe v2 $0.22/h, keyterms +$0.05/h, Scribe v2 Realtime $0.39/h, same
on every plan. Free tier includes 4.5 h batch and 2.5 h realtime.

## Verification

- `./scripts/test.sh`: 192 tests, 9 skipped, 0 failures. Mac Debug and iOS
  simulator builds succeed.
- Against the real API with a bogus key, through the app's code (throwaway test,
  deleted): batch → 401 `invalid_api_key` → `TranscriptionError.auth`;
  `validateElevenLabsKey` → rejected "Invalid API key"; realtime socket →
  `auth_error` → `LiveError.refused`, so live falls back to batch. The URL
  percent-encodes keyterms (`C%2B%2B%20%26%20Swift`).
- Offline: audio, commit and decode frames match the documented JSON; the
  keyterm filter drops over-long, over-five-word and duplicate terms; one hour
  prices at $0.27 batch with keyterms and $0.39 realtime.
- iPhone simulator: the Home grid shows Audio (9 min over 49 dictations); the
  ElevenLabs card rejects a bogus key with ElevenLabs' message.
- Mac Debug build: the Advanced pane shows the ElevenLabs section; Cost shows
  three tabs and the ElevenLabs price note (the period totals wrapped with
  three tabs and were fixed); the history header shows "of audio".
- The missing-permission branch of the key check is inferred from the docs
  (the real key is a full-access free-tier key).

## Verified with a real key (2026-09-29 morning)

The user left a free-tier ElevenLabs key on the Mac mini's desktop.

- `validateElevenLabsKey` → valid. `GET /v1/user` reports tier `free`.
- Batch through `elevenLabsTranscribe`, a 16 s synthetic dictation, keyterms
  "VoiceiQ" and "Priya": 1.9–2.6 s; both terms spelled right. `no_verbatim=true`
  dropped the leading "Um".
- Live through `LiveTranscriptionSession` + `ElevenLabsLiveDialect`, audio fed
  in real time as 100 ms chunks: setup 0.41–0.44 s; final 0.40–0.44 s after the
  last chunk. 16 s: complete, 17 partials. 73 s (two to three turn rolls at
  20–30 s): complete and in order, no lost or doubled words, 78 partials, and the
  mid-stream partial carried the earlier paragraphs.
- `session_started.config` echoed `no_verbatim: true` and
  `keyterms: ["VoiceiQ","Priya"]`, confirming the URL encoding. The realtime
  model still kept a leading "Um" with `no_verbatim`; the writing rules remove
  fillers anyway.
- iPhone simulator app: the key saved through Provider & Keys, the
  Transcription picker appeared, and ElevenLabs was selected. "Retry
  transcription" on a 21 s history entry ran Scribe v2 then Gemini 3.8 Flash
  through OpenRouter in 2.7 s. RAW: "So I wanted to check in about the launch
  plan. We should move the beta to Thursday. No, wait, Friday, … three tiers …".
  Result: the cleaned numbered list. Usage rows: `transcribe scribe_v2
  $0.001559` (21 s at $0.27/h with keyterms) and `cleanup
  google/gemini-3.8-flash`; the Cost page's ElevenLabs tab showed $0.0016 for
  one dictation.
- Mac Debug app: the key validated in Advanced, the Transcription switch
  (Gemini / ElevenLabs) appeared, and removing the key hid it again. The key was
  pasted from the clipboard and the clipboard cleared, and it was removed from
  this Mac afterwards.
- Not run: a spoken dictation on a physical iPhone or on the MacBook's
  installed app, which needs a new build there.

## Rollback

Remove the ElevenLabs key (or pick the provider) and every path is exactly the
provider's again. Code rollback is a revert of this change.
