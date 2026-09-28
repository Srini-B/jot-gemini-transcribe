# 2026-09-28: OpenAI as a fourth provider (macOS)

## Why

- Every provider the app had (Google AI Studio, OpenRouter, Vercel AI
  Gateway) served Gemini models. The owner asked for an OpenAI provider,
  selectable like the others, following the research note in
  `~/Desktop/gpt.md`: a transcription model first, then a cheap text model
  for the writing rules.

## Decisions

- Model per role: `gpt-transcribe` (batch), `gpt-live-transcribe` (live),
  `gpt-6-luna` (writing rules, Ask Anything, Translate, meeting notes),
  `gpt-4o-transcribe-diarize` (meetings, the only OpenAI model with speaker
  labels). Each is overridable in Settings → Advanced → OpenAI models, and the
  live delay is a picker (default `low`, as the research suggested).
- Two calls per dictation on this provider. Luna cannot take the FLAC, so the
  one-call path and the audio-checked cleanup are skipped. The research
  recommends the same split.
- The `GeminiClient` actor keeps one transport (`post`) for all four
  providers, so status mapping, deadlines and usage stay in one place.
- `LiveTranscriptionSession` gained a `LiveDialect` seam instead of a second
  session actor, so the ring, send order, turn rollover and finish rules are
  shared.
- Not built: Realtime 2.1 for Ask Anything, `gpt-realtime-translate` for live
  Translate, and the iOS Keys screen entry.

## Findings (probed with the owner's key)

- `/v1/audio/transcriptions` accepted FLAC although the docs list only
  mp3/mp4/m4a/wav/webm; FLAC, WAV and M4A gave the same text.
- Luna refuses `temperature: 0` and FLAC `input_audio` (wav/mp3 only).
- The realtime transcription socket refuses 16 kHz (minimum 24 kHz) and
  needs `turn_detection: null`.
- A keyword containing `<` fails the whole request with 400.
- `known_speaker_references[]` works with a FLAC data URL.

## Verification

- `swift test`: 193 tests, 0 failures. macOS app (`scripts/build.sh`) and
  the iOS app (simulator, unsigned) build.
- A throwaway test file (deleted afterwards) ran the real API through the app
  code: batch transcription 1.2 s, cleanup with the full prompt 1.6–2.5 s and
  accepted by the validation gate, live finish 0.67 s after commit, a 78 s
  live stream across a turn roll complete and in order, silence as `.silent`,
  diarization, notes JSON, and key validation (valid and rejected).
- Not verified: the Settings UI and a microphone dictation in the running
  app. The Debug build is signed differently from the installed app, so
  launching it raised Keychain password prompts for the stored gateway keys;
  they were denied and the Debug instance was quit.

## Follow-up: provider and gateway are separate choices (0.5.1)

### Why

- The owner corrected the model: OpenAI is not a fourth provider. The provider
  is Gemini or OpenAI; the gateway is that provider's own key, OpenRouter, or
  Vercel. Gateway keys are shared, so they are never asked for twice.
- Only the selected provider's key and models show in Settings. The Cost pane
  follows the selected provider but has a toggle to view the other.
- Privacy copy named Google for everything; it now names the active route.
- Every change ships as an installed, notarized build.

### What changed

- `ModelProvider` (gemini, openAI), `ModelGateway` (direct, openRouter,
  vercel), `ModelRoute`, and `ModelEndpoint` replace the four-case enum. The
  client, meetings, live session, Settings, onboarding, Cost pane, iOS Keys
  screen and privacy text read the route.
- The old `modelProvider` values `openRouter`/`vercel` read as Gemini plus that
  gateway, so existing installs keep their route.
- Build 0.5.1 (18, 19, 20) notarized with `scripts/release.sh` and installed
  to `/Applications`. 0.5.0 (17) was moved to the Trash as
  `VoiceiQ-0.5.0-build17.app`.

### Verification on the installed app

- The OpenAI key was pasted into Settings → Advanced from
  `~/Desktop/openai.txt` through the clipboard (cleared afterwards) and
  validated.
- OpenAI direct: a spoken 15 s dictation into TextEdit, `gpt-transcribe`
  2.1 s, Luna 5.2 s, inserted, history model `gpt-transcribe+gpt-6-luna`.
- OpenAI through OpenRouter: `openai/gpt-transcribe` returned the transcript
  and `openai/gpt-6-luna` returned an empty message, so the validation gate
  inserted the raw transcript. Two earlier runs that looked like empty
  transcripts were silent recordings: the mic did not hear the test speech
  while the default output was Jump Desktop Audio. After switching the output
  to the MacBook speakers (owner's instruction) the mic heard it.
- Cost pane: OpenAI view showed 4 calls, $0.0037, matching the logged
  charges; the Gemini view showed Gemini history and its pricing note.
- For the speaker tests, "Mute other audio while dictating" was turned off
  (`defaults write io.blue.voiceiq muteOtherAudioWhileDictating -bool false`)
  and the default output set to MacBook Air Speakers.

### Writing-model fixes found on the installed app (builds 21 and 22)

- Luna at `reasoning_effort: low` spent 232–752 reasoning tokens per cleanup
  through OpenRouter, once returning an empty message. A direct probe with
  the full prompt: `none` 1.4–2.5 s and no reasoning, `low` 1.9–4.7 s and up
  to 307 reasoning tokens. Build 21 uses `none` on both routes.
- With a screenshot of a TextEdit document that already held text, Luna
  copied that text into its answer (expansion ratios 1.9–5.8) and the gate
  pasted the raw transcript: 2 of 2 at `none`, 1 of 2 at `low`, 0 of 6 without
  the image. Build 22 sends no screenshots to the OpenAI writing model;
  `docs/PRIVACY.md` says so.
- The three gate rejections during testing turned writing rules off through
  the auto-degrade (3 trips in 24 h). Writing rules were switched back on and
  the trip log cleared.
- Build 22 on the installed app, same document with prior text: OpenAI direct
  turned a spoken three-item request into a numbered list (transcribe 1.5 s,
  cleanup 1.7 s); OpenAI through OpenRouter cleaned a two-sentence dictation
  (0.9 s + 1.3 s); Gemini direct still used the one-call path
  (`gemini-3.8-flash/one-call`, 3.5 s).
- After testing: provider OpenAI, gateway direct, "Mute other audio while
  dictating" back on, default output left on MacBook Air Speakers.

## Follow-up: screenshots for OpenAI, meeting routing, failed meetings (build 23)

### Why

- The owner wants OpenAI's writing model to see screenshots, without the
  screen text leaking into the dictation.
- Meetings need a diarizing model. With OpenAI over a gateway there is none,
  so meetings should use the OpenAI key, else Gemini.
- With no usable key, the recording should be kept as a failed meeting with
  the reason, for a manual Retry.

### Findings

- The leak was the message layout, not the wording. Measured on GPT-6 Luna
  with a screenshot of a TextEdit document full of earlier dictations: rules,
  transcript and image in one user message leaked in 3 of 9 runs; stricter
  wording in the same message 2 of 9; image before the rules 0 of 9 with 2
  empty answers; rules in a developer message and a user message holding only
  the labelled image and the transcript 0 of 29.
- Through the app's client with that layout: 0 of 9 leaks on the OpenAI API,
  0 of 9 through OpenRouter, all accepted by the gate; "super base" and
  "revenue cat" still came out as Supabase and RevenueCat.
- Meeting order: OpenAI+OpenRouter with every key → OpenAI direct, then
  Gemini over OpenRouter, direct, Vercel. No OpenAI or Gemini key but gateway
  keys → Gemini over the gateways. No keys → empty.
- `MeetingEngine` on a 17 s synthetic two-voice recording: no routes → saved
  as failed with the no-key reason, audio kept; OpenAI direct → done, two
  speakers, notes written.
- Installed build 23 (notarized, stapled): a spoken dictation into the
  TextEdit document with earlier text, screen context on, OpenAI direct:
  screenshot captured, Luna 1.8 s, inserted "Tell Priya the Supabase migration
  went out. The RevenueCat webhook is next." with nothing from the screen.
  Through OpenRouter, a three-item request came back as a numbered list.
- In the installed app, a failed meeting showed the no-key reason in a banner
  with Retry. With OpenAI over OpenRouter selected, Retry transcribed it with
  `gpt-4o-transcribe-diarize` on the OpenAI key (7.7 s, two speakers) and
  wrote notes with Luna. The test meeting was moved to the Trash afterwards.
- Unrelated crash found: AirPods connecting mid-dictation crashed the app in
  `AudioCaptureEngine.buildEngine` (`installTap` NSException during
  `WarmEnginePool.prewarmNext`). Same stack in 0.5.0 (17), so it predates
  this work; not fixed here.

## Follow-up: input-change crash, Experimental gateways, public docs (build 24)

### Why

- The app crashed when the default microphone changed (AirPods connecting).
- The owner wants the OpenRouter and Vercel options under a collapsed
  Experimental section.
- Public docs still described Gemini as the only provider.

### Crash

- Four crash reports on 2026-09-28, builds 17, 22 and 23: `SIGABRT` from an
  `NSException` in `-[AVAudioNode installTapOnBus:…]`, called from
  `AudioCaptureEngine.buildEngine` during `WarmEnginePool.prewarmNext`. The
  default input changed between reading the input format and installing the
  tap.
- Reproduced on the installed build 23: switching the default input between
  the MacBook mic and Jump Desktop Microphone 40 times at 150 ms crashed the
  app (a fifth report).
- Fix: `VoiceIQObjC` (`VoiceIQCore/ObjCSupport`), an Objective-C `@try`
  wrapper, around `installTap`, `prepare`, `start` and teardown in
  `AudioCaptureEngine` and around the iOS meeting mic tap. The exception
  becomes `CaptureError.deviceChanging`; a start or mid-recording rebuild
  retries once after 250 ms, and a failed prewarm is skipped.

### Settings

- Advanced now ends with a collapsible Experimental group, collapsed each time
  the pane opens, holding the Gateway picker and the OpenRouter and Vercel keys.

### Docs and copy

- README, CONTRIBUTING, docs/COST_TRACKING.md, docs/PRIVACY.md (meeting
  fallback to the other provider, item numbering), docs/RELEASING.md,
  docs/IOS.md (iPhone is Gemini-only), and in-app notices that named Gemini
  for every failure.

### Verification (build 25, installed and shipped as the DMG)

- Build 24 changed only the crash and docs; build 25 replaced the Experimental
  `DisclosureGroup`, which did not toggle inside the macOS Form, with a chevron
  button (accessibility value Collapsed/Expanded).
- The repro that crashed build 23 (40 switches at 150 ms) ran three times on
  build 24, plus runs at 60 ms and 300 ms, and once more on build 25: no crash,
  no new crash report. The log shows 28 `prewarm skipped: deviceChanging
  ("installTap: … Failed to create tap due to format mismatch …")` lines where
  the app used to abort.
- Eleven input switches during a hands-free dictation: the recording kept
  going across both logged switches ("Mic changed — kept recording") and the
  dictation was transcribed and inserted.
- Settings → Advanced on build 25: Experimental collapsed on open with no
  gateway controls in the window; expanded, it shows the Gateway picker and
  both gateway keys.
- `scripts/release.sh` (tests: 193, 0 failures): app and DMG notarized and
  stapled. A quarantined copy of `VoiceiQ-0.5.1.dmg` was assessed as
  "Notarized Developer ID" and its app is 0.5.1 (25) with a valid stapled
  ticket. Gatekeeper assessment is disabled on this Mac
  (`override=security disabled`), so the check proves signature and ticket,
  not a first-launch prompt on a tester's Mac.
