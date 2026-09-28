# 2026-09-28: iOS parity with the OpenAI provider (after macOS 0.5.1)

## Why

- 0.5.1 (25) on macOS added OpenAI as a provider and made the gateway a
  separate choice under Experimental. iOS got only the model changes: its
  client had no OpenAI key, its Keys screen treated the gateway picker as the
  provider, and the docs said the iPhone was Gemini-only. The owner asked for
  full parity, from onboarding through every section.

## What changed

- `AppModel` passes the OpenAI key and `OpenAIConfig` to `GeminiClient`, so
  dictation, Ask, Translate, live and meetings follow the selected route.
- Provider & Keys (Settings, and the onboarding key page, which shares
  `ModelKeysForm`): Gemini/OpenAI switch, that provider's own key, TinyFish,
  and a collapsed Experimental group with the Gateway picker (only when more
  than one route has a key) and the OpenRouter and Vercel keys. The entry was
  "API Keys"; it now holds the provider choice too, so it was renamed.
- Advanced: the session log, then only the selected provider's models (Gemini:
  endpoint, three models, previous endpoint toggle; OpenAI: three models and
  the live delay), as in the Mac's Advanced pane.
- Dictation: the live footer uses the Mac's wording (gateway, previous
  endpoint), shows `LiveStats.summary`, and turning live on clears the failure
  streak.
- Privacy names the active route's recipients (for example "OpenRouter, then
  OpenAI") and the meeting-notes provider.
- Cost (`UsageView.swift`, split out of `SettingsView.swift`): provider toggle
  opening on the selected provider, Today/Week/Month/All time, cost by action,
  and Detailed with per-model totals and recent calls; the footer names the
  price source as on the Mac.
- Debug only: `SimulatedMicrophone` now feeds the live PCM sink at real-time
  pace and saves exactly what it fed, so live transcription can be tested in
  the Simulator. Before, the live socket got no audio and every simulated
  live dictation fell back to the upload.

## Verification (iPhone 18 Pro Simulator, OpenAI key from the owner)

- Key saved and validated in Provider & Keys (pasted through the simulator
  clipboard, cleared afterwards).
- OpenAI direct: `gpt-transcribe` then `gpt-6-luna`, typed into Reminders.
- OpenAI direct with live: `gpt-live-transcribe` final 0.5 s after stop over
  20 s of audio, no upload, Luna 2.1 s, numbered list typed.
- OpenAI through OpenRouter: `openai/gpt-transcribe` 2.2 s and
  `openai/gpt-6-luna` 1.3 s; live disabled with the gateway footer.
- Meeting Redo with OpenAI over OpenRouter: `gpt-4o-transcribe-diarize` on the
  OpenAI key (10.4 s), notes by Luna (3.2 s). The test meeting's files were
  restored afterwards.
- Gemini through OpenRouter afterwards: one call to `google/gemini-3.8-flash`.
- Cost, Privacy and Advanced checked on screen. The simulator was left on
  Gemini with the OpenRouter gateway, as before; the OpenAI key stays saved.
- `./scripts/test.sh` 193 tests, 0 failures; `scripts/build.sh` and
  `scripts/build-ios.sh` pass.
- Not checked: the onboarding page on screen (same form as Settings) and a
  device build.
