# Privacy

## The promise

Your voice goes from your Mac directly to Google's Gemini API, using your own API
key. There is no middleman server, no account, no analytics, no telemetry.
Everything else stays on your Mac. The code is open — verify all of this.

## What leaves your machine (the complete list)

1. **The audio of each dictation** (FLAC-compressed), sent to
   `generativelanguage.googleapis.com` — the only network host this app talks to.
2. **Your dictionary terms**, alongside that audio. The transcription model uses
   them to bias what it hears, which is why names and jargon come out spelled
   right as you speak rather than being corrected afterwards. Only the correct
   spellings are sent — never the misspellings you record. They ride on every
   dictation, including with Smart transcription off.
3. **The writing-rules prompt**, while "Apply writing rules" is on in
   Settings → Dictation — on by default. It contains the transcript being
   formatted, the built-in formatting rules, your custom instructions from the
   same pane, a coarse tone category derived from the frontmost app's
   *category* (e.g. "chat message"), and your dictionary terms. With that
   setting off, your transcript text never leaves this Mac after transcription.
4. **Screen context**, while "Screen context" is on in Settings → Dictation — on
   by default. Voice IQ captures the main display when dictation starts and when
   the frontmost app changes during that dictation. It sends up to four reduced-
   size JPEG images to Gemini only with the writing-rules request. Voice IQ keeps
   the images in memory and never stores them on disk. macOS asks for Screen
   Recording permission the first time this feature runs. If you deny access,
   dictation continues without images. Turn off "Screen context" to stop capture.
5. **Meeting audio**, while "Record calls for meeting notes" is on in
   Settings → Dictation — on by default. When a calling app (Zoom, Teams,
   FaceTime, WhatsApp, Slack, Discord, Webex) or a browser tab on a meeting
   site is using your microphone, Voice IQ records your mic and the system audio,
   and on hang-up sends the mixed recording to Gemini for a speaker-labelled
   transcript, then sends that transcript back for a summary and action items.
   Both stay under `~/Library/Application Support/Voice IQ/meetings/`. Turn the
   setting off and nothing is recorded; you can also start and stop a meeting
   recording by hand from Settings → Meetings.
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
- Watch traffic with Little Snitch or `nettop` — you'll see exactly one host.
- Read the prompts: they are source files. The writing-rules pass is
  [PromptV1.swift](../JotCore/Sources/FormattingPipeline/PromptV1.swift) plus
  the default custom instructions in
  [DictationRulesSeed.swift](../JotCore/Sources/FormattingPipeline/DictationRulesSeed.swift);
  meeting transcription and summarising are in
  [GeminiClient+Meetings.swift](../JotCore/Sources/TranscriptionClient/GeminiClient+Meetings.swift).
