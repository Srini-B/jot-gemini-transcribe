# 2026-10-01: ElevenLabs credits reported as a bad key

## Report

After 0.5.9 (34) every dictation on the MacBook ended with "API key isn't
working — saved to History". The MacBook transcribes through ElevenLabs
Scribe v2; the writing model is GPT-6 Luna.

## What was checked

- The Keychain path did not change between build 33 and 34: `KeychainStore`
  only gained the agent-provider secret, the release entitlements and signing
  identity (`G8K3545FJ2.io.blue.voiceiq`) are unchanged, and
  `SettingsStore.transcriptionSource` only reads `.elevenLabs` when the key
  loads, so the key was read and sent.
- The ElevenLabs key lives in the data-protection keychain, which only the
  app can read; it could not be tested from a shell. The login keychain holds
  the Gemini, TinyFish, OpenRouter, Vercel and OpenAI keys (saved by builds
  that lacked the application identifier), not ElevenLabs.
- `GeminiClient.post` mapped every 401 to `TranscriptionError.auth` without
  reading the body, and logged nothing. ElevenLabs answers an exhausted
  credit balance with 401 `quota_exceeded`, the same status as a bad key.
  The user expected the balance to be used up.

Inferred, not measured: the balance is exhausted and the 401 carried
`quota_exceeded`. No failing request body was captured because the 401
branch did not log, and the MacBook's info-level log entries had already
rolled out.

## Change

- ElevenLabs 401: the `detail` kinds are logged at error level, and a quota
  or payment kind (`GeminiClient.isElevenLabsQuota`) maps to
  `rateLimitedDaily`; ElevenLabs 402 maps the same way. `RetryQueue`
  treats it as blocked, so the recording stays queued and drains once
  credits are added, instead of a dead `failed` row pointing at the key.
- Pill and queue copy for ElevenLabs say "ElevenLabs credits are used up"
  instead of "Daily quota reached", because the balance is monthly.

## Verification

- Debug compile passes.
- `scripts/release.sh` (SKIP_TESTS=1): notarization Accepted; still
  0.5.9 build 34. Installed on the MacBook (the running copy quit first)
  and relaunched; `spctl` reports Notarized Developer ID.
- Not exercised: a real quota 401 through the installed build. The next
  dictation on the MacBook will write the `detail` kinds to the log under
  `io.blue.voiceiq:transcription`, which settles whether it is quota or
  the key.
