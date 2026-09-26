# Privacy

## The promise

Your voice goes from your Mac directly to Google's Gemini API, using your own API
key. There is no middleman server, no account, no analytics, no telemetry.
Everything else stays on your Mac. The code is open — verify all of this.

## What leaves your machine (the complete list)

1. **The audio of each dictation** (FLAC-compressed), sent to
   `generativelanguage.googleapis.com` — the only network host this app talks
   to unless you add a TinyFish key (item 5).
2. **Your dictionary terms**, alongside that audio. The transcription model uses
   them to bias what it hears, which is why names and jargon come out spelled
   right as you speak rather than being corrected afterwards. Only the correct
   spellings are sent — never the misspellings you record. They ride on every
   dictation, including with Smart transcription off.
3. **The writing-rules prompt**, while "Apply writing rules" is on in
   Settings → Dictation — on by default. The dictation audio is attached to
   this request too (FLAC, up to 12 MB), so the writing model checks the words
   against what you said instead of trusting the live transcript. It contains the transcript being
   formatted, the built-in formatting rules, your custom instructions from the
   same pane, the frontmost app's name, and your dictionary terms. No tone or
   category is derived from the app; the model reads intent from your speech. With that
   setting off, your transcript text never leaves this Mac after transcription.
4. **Screen context**, while "Screen context" is on in Settings → Dictation — on
   by default. Voice IQ captures the main display when dictation starts and when
   the frontmost app changes during that dictation. It sends up to four reduced-
   size JPEG images to Gemini only with the writing-rules request. Voice IQ keeps
   the images in memory and never stores them on disk. macOS asks for Screen
   Recording permission the first time this feature runs. If you deny access,
   dictation continues without images. Turn off "Screen context" to stop capture.
5. **Ask Anything web search**, only if you saved a TinyFish API key in
   Settings → Advanced (off by default; there is no key until you add one).
   For each Ask Anything request Gemini first decides whether the question
   needs current information. If it does, Voice IQ sends one short search
   query to `api.search.tinyfish.ai` and fetches the top three result pages
   through `api.fetch.tinyfish.ai`. Your spoken instruction and any selected
   text go only to Google; TinyFish receives the search query and the page
   URLs. The fetched page text is placed in the Gemini prompt and discarded.
   Remove the key to stop this entirely.
5. **Meeting audio**, only after you start a recording. With "Offer to record
   calls" on in Settings → Dictation (on by default), Voice IQ watches whether a
   calling app (Zoom, Teams, FaceTime, WhatsApp, Slack, Discord, Webex) or a
   browser tab on a meeting site is using your microphone, and shows an offer
   in the pill. Nothing is recorded until you accept it, press the meeting
   shortcut (⌥M by default), or start one from Settings → Meetings. While
   recording, mic and system audio are streamed to the Gemini Live API for the
   live transcript shown in the pill and written to
   `~/Library/Application Support/Voice IQ/meetings/`. Recording stops only
   when you stop it; the mixed recording is then sent to Gemini for a
   speaker-labelled transcript, and that transcript is sent back for a summary
   and action items. Turn the setting off and no call detection runs.
6. **The selected text, when you use Ask Anything** (⌃⌥A by default). At the
   moment you press the shortcut, Voice IQ reads the text selected in the
   frontmost app through the Accessibility API and sends it with your spoken
   instruction to Gemini. Nothing else in the window is read. Translate (⌃⌥T)
   sends only your dictation, as a normal dictation does.
7. **Your API key**, in the request header to Google only. It is stored in the
   macOS Keychain, never in files or preferences.

The auto-learn feature ("Learn from your edits") never sends anything. It
re-reads the field Voice IQ typed into, through the Accessibility API, for up to ten
minutes after an insertion, and turns short replacements you made (one to
three words) into Dictionary entries. Those entries then ride with your audio like any other
dictionary term. Everything it reads stays on this Mac.

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

- One folder per dictation (`~/Library/Application Support/Voice IQ/recordings/`):
  crash-safe audio, transcript, metadata — this is what makes Retry and recovery work.
- Settings → Privacy & Storage: audio retention (24h / 7d / 30d / forever / never —
  "never" disables Retry), plus one-click **Delete all history**.
- Local files are protected by FileVault if enabled; they are not separately
  encrypted (stated honestly).

## Google's side of the wire

Your audio is governed by your own Gemini API terms with Google. As of writing,
paid-tier API usage is not used for model training; free-tier usage may be. That
relationship is yours — this app doesn't broker it. Review the
[Gemini API terms](https://ai.google.dev/gemini-api/terms).

## Secure input

When a password field is focused (secure input), dictation refuses to start, and
a transcript in flight is held in History only — never inserted, never placed on
the clipboard.

## Verify it

- Build from source (`./scripts/build.sh`).
- Watch traffic with Little Snitch or `nettop` — you'll see exactly one host
  (two TinyFish hosts appear only after you add a TinyFish key).
- Read the prompts: they are source files. The writing-rules pass is
  [PromptV1.swift](../VoiceIQCore/Sources/FormattingPipeline/PromptV1.swift) plus
  the default custom instructions in
  [DictationRulesSeed.swift](../VoiceIQCore/Sources/FormattingPipeline/DictationRulesSeed.swift);
  meeting transcription and summarising are in
  [GeminiClient+Meetings.swift](../VoiceIQCore/Sources/TranscriptionClient/GeminiClient+Meetings.swift).
