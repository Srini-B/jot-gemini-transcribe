# 2026-09-30: The transcription source applies to meetings

## Why

The owner picked ElevenLabs as the transcription source, but the 2026-09-30
meeting was transcribed by `gpt-4o-transcribe-diarize` (usage.sqlite: 41
dictations on `scribe_v2`, the meeting on the OpenAI diarizer). Meetings read
only the provider routes. The owner wants one choice for both, on macOS and iOS.

## What changed

- `MeetingTranscriber.SpeechRoute` (`.elevenLabs` or `.model(ModelRoute)`)
  replaces the provider list for transcription. `SpeechRoute.order` gives
  `[.elevenLabs]` when `SettingsStore.transcriptionSource` is ElevenLabs, as
  dictation does (no fallback to the provider), and the meeting routes
  otherwise. Notes still use the provider's meeting routes.
- `GeminiClient.elevenLabsDiarize` sends a window to Scribe v2 with
  `diarize=true` and word timestamps, verbatim, without keyterms, and books
  the cost under `meetingTranscribe`. Windows are 600 s of speech with the
  speaker reference clips inside the audio, linked by `SpeakerLinker.link`
  like Google's endpoint.
- The window cache is keyed by the first route (`transcribe-v6-<route>-<window>`),
  so Redo after changing the source transcribes again instead of reusing
  another model's windows.
- Both apps pass `transcriptionSource` to `MeetingEngine`. The ElevenLabs key
  footer on both apps and PRIVACY.md now say dictation and meetings.

## Verification

- VoiceIQCore suite passed. A throwaway test checked the Scribe response
  parser against the documented example (words kept, spacing and audio events
  dropped) and that ElevenLabs is the only meeting speech route when chosen.
- macOS and iOS Debug builds passed.
- Not run against the live ElevenLabs API: the key is in the app's
  data-protection keychain, which command-line tools cannot read.
