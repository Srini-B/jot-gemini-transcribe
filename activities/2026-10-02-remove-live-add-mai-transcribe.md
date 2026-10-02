# 2026-10-02: Live transcription removed, MAI Transcribe 2 added

## Request

Remove live (real-time) dictation entirely: the toggle, its models, settings
and UI. Add MAI Transcribe 2 as a transcription-only option, reachable through
the OpenRouter and Vercel AI Gateway keys the app already supports, and show a
Transcription provider picker beside the provider and gateway pickers.

Follow-up in the same session: offer MAI Transcribe 2 only when an OpenRouter
or Vercel key is stored, and hide the picker altogether when neither an
ElevenLabs nor a gateway key is stored, so the provider transcribes.

## Can MAI Transcribe 2 apply the writing rules?

No. It is speech-to-text only:

- OpenRouter's endpoint list for `microsoft/mai-transcribe-2` gives modality
  `audio->transcription`, output `transcription`, and an empty
  `supported_parameters` list (one provider, Azure, $0.10 an hour).
- Vercel's `/v1/models` types it `transcription`, input audio, output text,
  $0.00002778 a second ($0.10 an hour).
- Azure's MAI-Transcribe documentation lists keyword biasing
  (`phraseList.phrases`), a clean or verbatim style and a locale. It has no
  free-form prompt.

So it replaces the transcription stage the way ElevenLabs Scribe does, and the
selected provider's writing model applies the writing rules to its transcript.

Dictionary terms are not sent to it. OpenRouter documents a `keyterms` field
that only some providers accept (400 otherwise), and Vercel documents no
equivalent. Neither was probed: the gateway keys sit in the app's
data-protection keychain, which a shell cannot read. The writing rules still
receive the dictionary.

## Change

- Deleted the live stack: `TranscriptionClient/Live/` (sessions, dialects,
  WebSocket transport, PCM ring, failure stats), `LiveTranscriber`,
  `TranscriptDiff`, the coordinator's live session and partial text, the
  `polish` pass and its AUDIO prompt block, the PCM sink on the capture
  engine and the unused meeting-tap sinks, `liveModel`/`liveDelay`
  configuration and overrides, `ModelRoute.supportsLiveTranscription`,
  ElevenLabs realtime constants, `TimeoutPolicy.liveFinal`,
  `UsageStage.liveTranscribe`, `TokenUsage.fromLiveFrame`, live prices, the
  Dictation-pane and iPhone toggles, the live model fields on both apps, the
  pill's live text and eight test files that covered only live code.
- `FormattingSettingsMigration.removeLiveTranscriptionSettings` deletes the old
  defaults keys at launch on both apps.
- `TranscriptionSource.maiTranscribe`, `SettingsStore.maiTranscribeEndpoint`
  (chosen gateway when its key is stored, else OpenRouter, else Vercel), and a
  branch in `GeminiTranscriptionService.sendTranscribe` that calls the
  existing `gatewayTranscribe` with `microsoft/mai-transcribe-2`.
- The Transcription provider picker on the Mac (Settings → Advanced) and the
  iPhone (Provider & Keys) lists the provider, ElevenLabs when its key is
  stored, and MAI Transcribe 2 when a gateway key is stored. It is hidden when
  the provider is the only option.
- Error copy, the Privacy panes and `docs/PRIVACY.md` name the gateway and
  Microsoft when MAI transcribes. The Cost pane gained an MAI source.

## Verification

- `scripts/test.sh`: 133 tests pass.
- `scripts/build.sh` (macOS Debug) and `scripts/build-ios.sh` (iOS Simulator)
  build.
- Installed the notarized `scripts/release.sh` build (0.5.10, build 35, from
  the uncommitted tree) on the Mac mini. Settings → Advanced showed the
  Transcription provider picker with Gemini and MAI Transcribe 2 (gateway keys
  stored, no ElevenLabs key) and no live model field. Settings → Dictation had
  no Live transcription toggle.
- End to end through the installed app: a `say` recording (7.4 s) placed as an
  interrupted session and picked up by `RecoveryScanner` at launch.
  OpenRouter: `microsoft/mai-transcribe-2` 2.1 s, raw "He Priya UM, can you
  send me the quarterly report by Friday? Actually, make that Thursday.
  Thanks.", cleaned by `gemini-3.8-flash` to "Hi Priya, can you send me the
  quarterly report by Thursday? Thanks.", booked $0.000222. Vercel (gateway
  set to Vercel for one run): 1.9 s, booked $0.000149. History's model column
  read `microsoft/mai-transcribe-2+gemini-3.8-flash` both times. The test rows
  and folders were deleted afterwards and the settings restored.
- Not verified: the picker hidden with no ElevenLabs or gateway key (the
  stored keys were left alone), and the iPhone app beyond a Simulator build.
- The Vercel run's cleanup booked no usage row because the stored Vercel key
  is on the free tier, which refuses `google/gemini-3.8-flash` (seen in the
  meeting run below), so the cleanup returned the raw text.

## Follow-up: MAI Transcribe 2 for meetings

Meetings already followed the transcription source: ElevenLabs Scribe v2
diarizes each window, with reference clips of known speakers inside the
audio. The user asked for the same with MAI Transcribe 2, which Azure
documents with speaker diarization and word timestamps.

Probed through the installed app (the gateway keys are readable only there)
on a synthetic 40 s call, one mic voice and two far-side voices:

- OpenRouter's own `diarize` field: 400 "The selected model does not support
  diarize". `verbose_json` alone gave words and segments without speakers.
  Azure's options through `provider.options.azure` (`diarization.enabled`,
  `modelOptions.timestamps: word`) gave all 97 words with `speaker` 0/1/2,
  matching the three voices.
- Vercel: `providerOptions.azure` with `modelOptions`, `diarize`,
  `diarizationEnabled` or `speakerDiarization` is refused as "invalid azure
  provider options". `diarization: {enabled: true}` and a flat
  `timestamps: word` are accepted; speakers then appear only in
  `providerMetadata.azure.phrases`, with words timed in milliseconds.

Change: `MeetingTranscriber.SpeechRoute.mai(ModelEndpoint)`, handled like
ElevenLabs (600 s windows, reference clips inside the audio, labels linked by
`SpeakerLinker`), `GeminiClient.maiDiarize` for both gateways, and
`SettingsStore.meetingTranscriptionRoute` replacing the `transcriptionSource`
closure `MeetingEngine` took. Azure says diarization fails on recordings of
about 15 minutes; the 600 s window stays under that.

Verified with the final notarized build, via Retry in Settings → Meetings on
the same synthetic call: OpenRouter 1.8 s and Vercel 3.1 s, both seven turns
under the right three speakers with word times, about $0.0011 each, notes
written by Gemini. Google's endpoint on the same audio lost one turn. No route,
MAI included, marked the mic voice as "You" on this synthetic call. Not run:
a meeting longer than one window. The test meeting was deleted and the
settings restored afterwards.

## Cost Analysis and release

The Cost pane's Source picker gained MAI (`CostSource.mai`). Beside the period
totals, four segments squeezed "Today" and "This week" to "$0.01…", so the
picker moved to its own row above them. Checked on the installed notarized
0.5.11 (36) build: MAI shows $0.0125, 11 meeting calls and 2 others, matching
`usage.sqlite`. Released as 0.5.11 (36).
