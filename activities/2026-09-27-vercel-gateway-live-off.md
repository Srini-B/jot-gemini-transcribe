# 2026-09-27 — Live transcription opt-in, meeting preview removed, Vercel AI Gateway

## Why

The AI Studio key's live model (`gemini-live`) has its own small
requests-per-day quota. A long dictation rotates through several live sessions,
and the meeting live preview rotated one every 540 s for the whole meeting, so
a single 20-minute meeting plus a few dictations exhausted the day's live quota
and every later dictation failed into the batch path with a 429. The live
preview was also the source of the "frozen transcript on the pill" reports for
long dictations and meetings.

The owner's request: stop live transcript on meetings entirely (processing
time after stop is acceptable), turn live off by default for everyone, force
it off once for existing installs and let them opt back in, add Vercel AI
Gateway as a third provider, and move the provider picker into its own section.

## What changed

- `MeetingLivePreview` deleted with `MeetingEngine.makeLiveSession` /
  `livePreview`, `DictationController.makeMeetingPreviewSession`, and
  `PillModel.meetingPreview`. The `meetingRecording` pill is fixed at 300 pt:
  clock, wave, "Recording meeting", stop. The `pcmSink` hooks on `MicTap` and
  `SystemAudioTap` stay (unused, harmless) in case a later feature needs PCM.
- `SettingsStore.liveTranscription` defaults to false.
  `FormattingSettingsMigration.disableLiveTranscriptionOnce` (flag
  `didDisableLiveTranscription`) runs from `AppDelegate` after
  `enableWritingRulesIfNeeded` and writes `liveTranscription = false` once.
  The Settings → Dictation toggle persists any later choice.
- `ModelProvider.vercel`; `resolve(preferred:available:)` takes a set of
  providers with stored keys (order Gemini → OpenRouter → Vercel).
  `KeychainStore.Secret.vercel`, `providersWithKeys`, `hasModelKey` derived
  from it. `GeminiClient+OpenRouter.swift` became `GeminiClient+Gateways.swift`
  with `gatewayTranscribe(via:)` / `gatewayChat(via:)`. Vercel transcription
  uses the AI SDK transcription protocol
  (`POST /v4/ai/transcription-model` with the `ai-*` headers); chat uses
  `/v1/chat/completions` with a `file` audio part and
  `response_format: {type: json}`. `TokenUsage.fromOpenAI` (renamed from
  `fromOpenRouter`) plus `fromVercelTranscription` for the protocol response.
  `PriceBook.price(for:)` strips `google/`.
- `OpenRouterKeySection.swift` replaced by `GatewayKeySection.swift`:
  `GatewayKeySection(.openRouter)`, `GatewayKeySection(.vercel)`, and
  `ProviderSection` (picker of providers with keys, shown only with two or
  more). Advanced pane order: Provider, Gemini, OpenRouter, Vercel, TinyFish,
  overrides.

## Verification

- `swift test --package-path VoiceIQCore`: 193 tests, 9 skipped, 0 failures
  (`testLiveTranscriptionDefaultsToOffAndLiveModelOverrideApplies` updated to
  the new default).
- `./scripts/build.sh` clean; Developer-ID quick release installed to
  /Applications and launched. After launch: `defaults read io.blue.voiceiq
  liveTranscription` → 0, `didDisableLiveTranscription` → 1, log line
  "live transcription migration: switched off, now opt-in".
- Vercel probed with the owner's key: transcription protocol 200 with
  `providerMetadata.gateway.cost`; chat completions return `usage.cost`; the
  `file` audio part and both `json` / `json_object` formats accepted on
  `google/gemini-2.5-flash-lite`.
- Real dictation via Vercel: transcribe usage row
  `google/gemini-3.5-transcribe … $0.00065` with reported cost; cleanup
  returned 403 `RestrictedModelsError` ("Free tier users do not have access
  to this model") for `google/gemini-3.8-flash`, so the dictation landed raw
  with "cleanup unavailable … inserting raw". The owner's Vercel account is
  free tier; cleanup, meeting notes, Ask Anything, and Translate need paid
  credits there. The key validator (`GET /v1/models`) cannot detect this.
- Real dictation via OpenRouter: transcribe and cleanup usage rows, state →
  done, text inserted.
- Advanced pane screenshot-checked with all three keys stored (Provider
  picker visible, three key sections, uniform styling).
- Not exercised: a real meeting recording with the preview removed (would
  need a live call); the remaining branch is the pre-existing no-preview
  layout.

## Rollout notes

Existing installs lose live transcription once at the next launch of this
build. Users who want it back turn it on in Settings → Dictation; the flag
prevents a second forced switch. Test-time settings were restored:
`muteOtherAudioWhileDictating` true, `modelProvider` `openRouter`.

## Addendum: dictation key accepts combinations

The dictation key only took a bare modifier (fn, sided ⌘ ⌥ ⌃) while every
other shortcut took modifier + key. Users without a spare modifier had no
option. `DictationTrigger` now carries either form; the recorder in
Settings → Dictation takes whichever is pressed and refuses a combo that
another shortcut already owns (inline caption names the owner).

Verified on the installed build: recording ⌥M showed "Left ⌥M is already
used by Meeting recording." and stayed in recording mode; recording right ⌥D
stored `{"combo":…,"side":"right"}` and showed a Side picker; with that
trigger, left ⌥D typed ∂ into TextEdit and started nothing, right ⌥D started
and stopped a dictation that transcribed and inserted (`state → done(inserted)`),
and ⌥M still toggled a meeting. The stored key stays `Right ⌥` after testing.

Observed once, not reproduced: after an accidental 90 s meeting recording in
the same process, two dictations captured pure digital silence
(`peak tap=0.000`, room −120 dBFS) while a separate process heard the mic at
0.23 peak. A restart cleared it; a 4 s meeting followed by a dictation in the
new process worked. Worth watching for a mic tap that does not release.
