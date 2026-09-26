<div align="center">

<img src="docs/images/icon.png" width="128" alt="Voice IQ">

# Voice IQ

**[Gemini 3.5 Transcribe](https://ai.google.dev/gemini-api/docs/models/gemini-3.5-transcribe) Demo. Hold a key. Speak. It types.**

Smart dictation for macOS that puts polished text wherever your cursor is.

<sub>Created by [Ammaar Reshi](https://x.com/ammaar) · Apache 2.0 licensed</sub>

</div>

This is not an officially supported Google product.

---

## What it is

Hold `fn`, say the thing, let go. A moment later your words are in the app you
were already using — punctuated, filler words removed, cleaned up. No window to switch
to, no transcript to copy, no account to make.

<img width="640" height="294" alt="Voice IQ preview" src="https://github.com/user-attachments/assets/669efea9-dbfe-4174-a8fe-748aab818f14" />


It is deliberately small: a menu bar icon, a pill at the bottom of your screen
while you talk, and a History window that proves nothing was ever lost.

## The three gestures

| Gesture | What happens |
| --- | --- |
| **Hold `fn`** | Records while held. Release and the text lands at your cursor. |
| **`fn` + tap `Space`** | Hands-free: keeps recording after you let go. Tap `fn` to finish. |
| **`Esc`** | Cancels. Anything over 10 seconds is still kept in History. |

The key is rebindable in Settings → General if `fn` is spoken for.

## What makes it different

**It follows a change of mind.** Say *"let's meet at 1pm — actually, no, make it
2pm"* and Voice IQ writes **"Let's meet at 2pm."** That is the whole pitch, and
onboarding makes you do it once so you believe it.

**It never loses your words.** Audio goes to disk from the first millisecond, so
a crash, a `kill -9`, or a flat battery costs you nothing — the recording is
recovered on next launch. Offline, dictations queue and land when you reconnect.
Every failure is retryable from History. Release the key mid-word and it keeps
listening until you actually stop.

**It is private by architecture.** Your voice goes from your Mac straight to the
Gemini API with *your* key. No middleman server, no account, no analytics, no
keystroke logging — one network host, and you can read every line of the code
that talks to it. Screen context (a few downscaled screenshots sent with each
dictation so on-screen names and paths are spelled right) can be switched off
in Settings → Dictation. See [PRIVACY.md](docs/PRIVACY.md).

**Your jargon, spelled right.** Names and product terms go in the Dictionary and
ride along with the audio, so the model hears "Kubernetes" instead of guessing
"cooper netties" — corrected at the source, not patched afterwards. Fix a word
after Voice IQ types it and the correction is learned into the Dictionary on its own.

**It writes the way you meant it.** A writing-rules pass runs on every
transcript: "scratch that", "change the first point to…" and other mid-dictation
instructions become edits, run-on speech gets sentence breaks, and your own
rules from Settings → Dictation are applied. Dictate for as long as you like;
there is no time limit.

**Ask Anything and Translate.** Select text (optional), hold ⌃⌥A, and ask
("make this shorter", "what does this error mean"); the answer opens in the
pill, with Markdown rendered and a Copy button, and never edits your text. Each
question stands alone. Add a free [TinyFish](https://agent.tinyfish.ai/api-keys)
API key in Settings → Advanced and questions that need current information
(news, prices, releases) are answered from a live web search, with sources
linked. Hold ⌃⌥T to dictate in any language and have it typed in
the target language you pick from the searchable list in Settings → Dictation
(the 99 languages Gemini Live supports); if Gemini cannot translate it, the pill
says so and nothing is inserted. ⌘⇧V pastes the last transcript or answer
again. All three shortcuts are editable and can require either, left, or right
modifier keys. Plain dictation is language-agnostic: speak in any language, or
mix them mid-sentence, and the text stays in the language you used.

**Stays out of your way.** Other audio is muted while you dictate and restored
after (switch it off in Settings → Dictation). Pick a preferred microphone or
leave it on system default and get a one-time notice when a new one appears.

**Meeting notes, hands-free.** When Zoom, Teams, FaceTime, WhatsApp, Slack,
Discord, Webex, or a Meet/Teams/Zoom tab in any browser is on a call, Voice IQ
records both sides, and on hang-up produces a speaker-labelled transcript plus a
summary, decisions, and owned action items under Settings → Meetings.

## Install

1. Download the latest `Voice IQ-x.y.z.dmg` from [Releases](../../releases/latest).
2. Drag Voice IQ into **Applications** and launch it from there — apps run from a
   mounted disk image are sandboxed by macOS and the permissions you grant will
   not stick.

<div align="center">
<img src="docs/images/installer.png" width="480" alt="Drag Voice IQ to Applications">
</div>

Setup takes about two minutes and the app walks you through it:

1. **Paste a Gemini API key** — get one at
   [Google AI Studio](https://aistudio.google.com/apikey). It is stored in your
   macOS Keychain and only ever sent to Google.
2. **Allow the microphone** — say hello and it advances by itself.
3. **Allow Accessibility** — macOS requires this for any app that types into
   another app.
4. **Hold `fn` and talk.**

**Cost:** you pay Google for what you dictate at
[Gemini API pricing](https://ai.google.dev/pricing); a free tier exists and a
typical dictation is a few seconds of audio. Voice IQ itself is free and has no
account.

**Models:** Voice IQ transcribes with `gemini-3.5-transcribe-live` while you speak
(the live socket) and `gemini-3.5-transcribe` for the batch path, then applies
writing rules and writes meeting notes with `gemini-3.8-flash`. Your key needs
access to them; setup tells you up front if it does not, instead of failing on
your first dictation. Advanced settings can pin other model names.

## How it works

```
fn down ─▶ capture (CAF on disk from t=0) ─▶ fn up ─▶ FLAC ─▶ Gemini transcribe
                        │  (live socket streams text meanwhile)        │  (chunked past 10 min)
                        ▼                                              ▼
   cursor ◀─ insert (AX → paste → clipboard) ◀─ validate ◀─ writing-rules pass
      │                                                     (gemini-3.8-flash)
      ▼                                                            │
   learn from edits ─▶ Dictionary                            History (SQLite)
```

A few decisions worth knowing about, because they are what make it feel solid:

- **The capture graph is pre-warmed while idle**, so a key press only pays
  `engine.start()` — 20-40ms instead of 75-150ms. Preparing is not recording: no
  audio flows and no mic indicator appears until you actually hold the key.
- **The mic drains one buffer past the stop**, because the audio tap only
  delivers whole ~100ms chunks and tearing down immediately threw away the tail
  of your last word.
- **Insertion is a ladder**: Accessibility API first (no clipboard involved), then
  a guarded paste that restores your clipboard, then a "copied — press ⌘V" chip.
  It never blind-pastes into an app that stole focus mid-flight.
- **A validation gate** guards the writing-rules pass, catching the classic failure where the model *answers*
  your audio instead of transcribing it, and falls back to the raw transcript.
- **The paths that can lose words are tested.** `VoiceIQCore` is a headless Swift
  package holding the state machine, hotkey grammar, audio, transcription,
  formatting, insertion and history — so the failure modes above are exercised
  without launching the app.

The full design specs — including the failure matrix the reliability work is
built from — are in [docs/design/](docs/design/).

## Development

Requires macOS 14+, Xcode 16+, and [xcodegen](https://github.com/yonaskolb/XcodeGen).
The `.xcodeproj` is generated, not checked in.

```bash
brew install xcodegen
./scripts/build.sh          # xcodegen generate + xcodebuild
./scripts/test.sh           # swift test on VoiceIQCore
open VoiceIQ.xcodeproj          # or work in Xcode
```

Debug builds sign ad-hoc, so a clean clone needs no Apple account, certificate,
or team membership — `./scripts/build.sh` works as-is. To build under your own
team instead: `./scripts/build.sh DEVELOPMENT_TEAM=XXXXXXXXXX`. Only release
builds (`scripts/release.sh`) need a real Developer ID.

```
App/            menu bar item, HUD pill, windows, design tokens, icon + sounds
VoiceIQCore/        all engine logic, headless and testable
  HotkeyEngine/     CGEventTap + the pure hold/lock/cancel grammar
  AudioEngine/      crash-safe CAF capture, device changes, prewarming
  TranscriptionClient/  Gemini calls, timeouts, retries, FLAC
  FormattingPipeline/   cleanup prompt, validation gate, dictionary rules
  InsertionEngine/      the AX → paste → clipboard ladder
  HistoryStore/         GRDB index, recovery, retry queue, retention
scripts/        build, test, icon, DMG, release
docs/           privacy, releasing, design specs, research
```

Useful while hacking:

```bash
# every surface is reachable headlessly
open "voiceiq://settings/about"      # or /dictation /privacy /advanced
open "voiceiq://history"  "voiceiq://dictionary"  "voiceiq://onboarding/5"

# watch it work
log show --last 5m --info --predicate 'subsystem == "io.blue.voiceiq"'
```

Transcript text is logged as `private` and never appears in those logs.

### Releasing

`./scripts/release.sh` archives, signs with Developer ID, notarizes, staples,
and builds the installer DMG. It refuses to produce a shareable DMG that is not
notarized. See [docs/RELEASING.md](docs/RELEASING.md) for the certificate setup.

## License

Apache License 2.0 — see [LICENSE](LICENSE). Bundled fonts (Google Sans Flex,
Google Sans Code) are SIL OFL 1.1. The earcons are original works covered by the
same Apache 2.0 license. Details in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
