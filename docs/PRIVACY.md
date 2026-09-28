# Privacy

## The promise

Your voice goes from your Mac directly to the model provider you chose in
Settings → Advanced, using your own API key: Google's Gemini API or OpenAI's API.
If you choose a gateway instead (OpenRouter or Vercel AI Gateway), requests go
to that gateway with your gateway key, and it forwards them to the provider.
There is no VoiceiQ server, no account, no analytics, no telemetry. Everything
else stays on your Mac. The code is open — verify all of this.

"The provider" below means whichever of these the active route sends to:
`generativelanguage.googleapis.com` (Gemini), `api.openai.com` (OpenAI),
`openrouter.ai`, or `ai-gateway.vercel.sh`. Only one of them receives a given
dictation; nothing is sent to the others. Meetings are the one exception: they
need a model that labels speakers, so with OpenAI selected through a gateway a
meeting goes to OpenAI with your OpenAI key, or to Gemini when there is no
OpenAI key, and a meeting whose provider fails moves on to the other provider
you have a key for. With no usable key, nothing is sent and the recording stays
on your Mac.

## What leaves your machine (the complete list)

1. **The audio of each dictation** (FLAC-compressed), sent to the provider —
   the only network host this app talks to unless you add a TinyFish key
   (item 5). With live transcription on, the audio streams to the provider over
   a WebSocket while you speak (the provider's own API only).
2. **Your dictionary terms**, alongside that audio. The transcription model uses
   them to bias what it hears, which is why names and jargon come out spelled
   right as you speak rather than being corrected afterwards. Only the correct
   spellings are sent — never the misspellings you record. They ride on every
   dictation, including with Smart transcription off.
3. **The writing-rules prompt**, while "Apply writing rules" is on in
   Settings → Dictation — on by default. With Gemini the dictation audio is
   attached to this request too (FLAC, up to 12 MB), so the writing model
   checks the words against what you said instead of trusting the live
   transcript. OpenAI's writing model takes no audio, so with OpenAI only text
   (and screen images, item 4) is sent. It contains the transcript being
   formatted, the built-in formatting rules, your custom instructions from the
   same pane, the frontmost app's name, and your dictionary terms. No tone or
   category is derived from the app; the model reads intent from your speech. With that
   setting off, your transcript text never leaves this Mac after transcription.
4. **Screen context**, while "Screen context" is on in Settings → Dictation — on
   by default. VoiceiQ captures the main display when dictation starts and when
   the frontmost app changes during that dictation. It sends up to four reduced-
   size JPEG images to the provider only with the writing-rules request. VoiceiQ keeps
   the images in memory and never stores them on disk. macOS asks for Screen
   Recording permission the first time this feature runs. If you deny access,
   dictation continues without images. Turn off "Screen context" to stop capture.
5. **Ask Anything web search**, only if you saved a TinyFish API key in
   Settings → Advanced (off by default; there is no key until you add one).
   For each Ask Anything request the provider's model first decides whether
   the question needs current information. If it does, VoiceiQ sends one short search
   query to `api.search.tinyfish.ai` and fetches the top three result pages
   through `api.fetch.tinyfish.ai`. Your spoken instruction and any selected
   text go only to the provider; TinyFish receives the search query and the
   page URLs. The fetched page text is placed in the provider prompt and
   discarded.
   Remove the key to stop this entirely.
6. **Meeting audio**, only after you start a recording. With "Offer to record
   calls" on in Settings → Dictation (on by default), VoiceiQ watches whether a
   calling app (Zoom, Teams, FaceTime, WhatsApp, Slack, Discord, Webex) or a
   browser tab on a meeting site is using your microphone, and shows an offer
   in the pill. Nothing is recorded until you accept it, press the meeting
   shortcut (⌥M by default), or start one from Settings → Meetings. While
   recording, mic and system audio are written to
   `~/Library/Application Support/VoiceiQ/meetings/` and nothing is sent.
   Recording stops only when you stop it; the stretches with speech are then
   sent to the provider for a speaker-labelled transcript, and that
   transcript is sent back for a summary and action items. Turn the setting off and no call detection runs.
7. **The selected text, when you use Ask Anything** (⌃⌥A by default). At the
   moment you press the shortcut, VoiceiQ reads the text selected in the
   frontmost app through the Accessibility API and sends it with your spoken
   instruction to the provider. Nothing else in the window is read. Translate (⌃⌥T)
   sends only your dictation, as a normal dictation does.
8. **Your API keys**, each only in the request header to its own service: the
   Gemini key to Google, the OpenAI key to OpenAI, a gateway key to that
   gateway. They are stored in the macOS Keychain, never in files or
   preferences.

The auto-learn feature ("Learn from your edits") never sends anything. It
re-reads the field VoiceiQ typed into, through the Accessibility API, for up to ten
minutes after an insertion, waits until you have stopped editing for a few
seconds, and adds the short replacements you made (one to three words) to the
Dictionary as words. They ride with your audio like any other dictionary term
and are never applied as automatic text replacements. Everything it reads stays on this Mac.

## What never leaves

- Your history database and stored recordings — audio and transcript text leave
  only as part of the requests above, never in bulk and never anywhere else
- Your dictionary as a file. Individual terms ride with the audio as described
  above, and your misspelling rules are included in the writing-rules prompt
  while that pass is on. The store itself, and everything you have not
  dictated against, stays on this Mac
- Which apps you use, when you dictate, or anything you type
- Keystrokes: the event tap watches your dictation key, plus — only while a
  dictation is active — Esc (cancel), Space (the hands-free gesture), and the
  *fact that* another key was pressed (the accidental-chord guard; which key it
  was is never examined beyond its keycode, never logged, never stored, never
  transmitted). When you're not dictating, other keys pass through untouched.
- Screen context images are never stored on disk and are never attached to Ask
  Anything, Translate, meeting, or transcription requests.
- Telemetry: there is none. No analytics SDK, no crash uploader, no phone-home.

## What's stored locally, and your controls

- One folder per dictation (`~/Library/Application Support/VoiceiQ/recordings/`):
  crash-safe audio, transcript, metadata — this is what makes Retry and recovery work.
- Settings → Privacy & Storage: audio retention (24h / 7d / 30d / forever / never —
  "never" disables Retry), plus one-click **Delete all history**.
- Local files are protected by FileVault if enabled; they are not separately
  encrypted (stated honestly).

## The provider's side of the wire

Your audio is governed by your own terms with whoever receives it. With Gemini,
that is the Gemini API terms with Google; as of writing, paid-tier API usage is
not used for model training, and free-tier usage may be. With OpenAI, it is
OpenAI's API terms. Through a gateway, the gateway's terms apply as well as the
provider's. That relationship is yours — this app doesn't broker it. Review the
[Gemini API terms](https://ai.google.dev/gemini-api/terms), the
[OpenAI API data controls](https://platform.openai.com/docs/guides/your-data),
and your gateway's policy.

## Secure input

When a password field is focused (secure input), dictation refuses to start, and
a transcript in flight is held in History only — never inserted, never placed on
the clipboard.

## Verify it

- Build from source (`./scripts/build.sh`).
- Watch traffic with Little Snitch or `nettop` — a dictation reaches exactly
  one model host, the one the active route names (two TinyFish hosts appear
  only after you add a TinyFish key).
- Read the prompts: they are source files. The writing-rules pass is
  [PromptV1.swift](../VoiceIQCore/Sources/FormattingPipeline/PromptV1.swift) plus
  the default custom instructions in
  [DictationRulesSeed.swift](../VoiceIQCore/Sources/FormattingPipeline/DictationRulesSeed.swift);
  meeting transcription and summarising are in
  [GeminiClient+Meetings.swift](../VoiceIQCore/Sources/TranscriptionClient/GeminiClient+Meetings.swift),
  and OpenAI's requests in
  [GeminiClient+OpenAI.swift](../VoiceIQCore/Sources/TranscriptionClient/GeminiClient+OpenAI.swift).
