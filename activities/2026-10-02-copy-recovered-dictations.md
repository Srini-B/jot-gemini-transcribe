# 2026-10-02: Copy recovered dictations to the clipboard; MAI style and recovery findings

## MAI-Transcribe-2 transcription style

- Azure documents `enhancedMode.modelOptions.transcribeStyle`: `"verbatim"` (the default) or `"clean"`. Verbatim keeps fillers ("um", "uh"), false starts and self-corrections. Clean removes fillers and "auto-formats common speech patterns". Sources: [Azure MAI-Transcribe docs](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/mai-transcribe) and the [model card](https://microsoft.ai/pdf/MAI-Transcribe-2-Model-Card.pdf).
- `GeminiClient.gatewayTranscribe` sends only `model` + `input_audio` (OpenRouter) or `audio` + `mediaType` (Vercel). No style is sent, so every MAI dictation got Azure's default: verbatim.
- Both gateways forward Azure options:
  - OpenRouter: `provider.options.azure`. Unknown keys are silently dropped.
  - Vercel: `providerOptions.azure` with flat keys.
  - `maiDiarize` already sends `modelOptions.timestamps` (OpenRouter) and flat `timestamps` (Vercel).
- Clean would therefore most likely be `provider.options.azure.modelOptions.transcribeStyle = "clean"` on OpenRouter and `providerOptions.azure.transcribeStyle = "clean"` on Vercel.
- Not probed: no gateway key is readable outside the app's keychain.

## Recent MacBook dictations (0.5.11 build 36 release, signed 11:07 IST; no fresh-session retry or filler fallback in that binary)

- 13:10:51 IST, `B726615B` ("offline", then recovered):
  - The ElevenLabs request reused an HTTP/3 connection that had been idle for 72 s. The server answered with a QUIC stateless reset, and the request failed after 42 ms with `-1005` (connection lost).
  - CFNetwork did not retry the non-idempotent POST.
  - `GeminiClient.post` maps `.networkConnectionLost` to `TranscriptionError.offline`, and `transcribeWithRetry` retries only `.network`/`.timeout`. The coordinator therefore queued the dictation and showed "You're offline — saved to History", although Wi-Fi was up.
  - 11 s later, right after History was opened from the menu, the retry ran on a fresh connection: transcribe 1.27 s, cleanup gpt-6-luna 1.30 s. No retry-queue drain was logged, so this was History's Retry.
  - Cleaned text equals raw because the model changed nothing.
- 13:09:10 and 13:07:55 IST: ElevenLabs scribe_v2, then gpt-6-luna cleanup, each in one attempt (3.25 s and 4.50 s, HTTP/3, reused connection). The gate accepted both, and no error note was stored.

## Change

- New `RecoveryNotice` (VoiceIQCore) holds the recovery pill copy and builds the clipboard text.
- `RetryQueue.onDrained` now passes the recovered texts.
- `RetryOutcome.recovered(text:)` carries the new text.
- `RecoveryScanner.onRecovered` passes the recovered text.
- New setting `copyRecoveredToClipboard`, with a toggle in Settings → Dictation.
- `DictationController` copies the recovered text when the setting is on, and says "copied to the clipboard" only when the copy succeeded.
- iOS keeps its banners.

## Verification

- `swift test`: 140 tests, 0 failures, including 7 new `RecoveryClipboardTests`.
- iOS scheme built with code signing off.
- `scripts/release.sh` (`SKIP_TESTS=1`) built a signed, notarized 0.5.11, accepted by `spctl` and stapled. It was installed on the Mac mini.
- With the setting on, three synthetic queued dictations were recovered by the launch drain. Each time the clipboard went from a sentinel to the recovered text, and the History row stayed `recovered` with the text. The AX tree showed the new toggle.
- The pill itself could not be captured: screen capture is unavailable from the runner, and the pill window exposes no AX text. Its wording is covered by unit tests.
- The test rows and the setting were removed, and the previously installed app was restored.
