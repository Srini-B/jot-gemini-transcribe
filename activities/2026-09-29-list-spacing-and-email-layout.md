# 2026-09-29: List spacing and email layout in the writing rules

## Why

The owner found lists visually congested and dictated emails not laid out as
emails. App-based classification stays out (rejected on 2026-09-26: intent
comes from the speech), so both fixes are prompt rules.

## Research

- VoiceInk (GPL-3.0) and FluidVoice (GPL-3.0) show the email layout only
  through examples: greeting, blank line, body, blank line, sign-off, name on
  the next line. Both put list items on consecutive lines. OpenWhispr and
  Handy (MIT) and Whispering (AGPL) have no list-spacing or email-layout
  rule. None has a nested-list or subject-line rule. Studied for behavior
  only; no wording copied.
- Wispr Flow and VoiceInk pick an email style from the destination app,
  including web mail by URL (Wispr: "Gmail in Chrome is Email"). Not adopted
  here, per the 2026-09-26 decision.

## What changed

- `PromptV1.rules`: a blank line around every list and between top-level
  items that are sentences. Lists of short phrases stay tight, and nested
  sub-items sit directly under their item. Paragraphs are separated by one
  blank line. New email rule: a spoken greeting followed by a spoken sign-off
  or name, or by more than one paragraph, is laid out as greeting line, body
  paragraphs, sign-off, and name, with blank lines between the blocks. A
  greeting with a one-paragraph message and no sign-off stays inline. Nothing
  unspoken is added.
- `PromptV1.examples`: list examples now carry the blank lines. Added an email
  with a list and sign-off, and a one-line greeting that stays inline.
  `layoutReminder` restates both rules.
- `DictationRulesSeed`: the same two rules and a closing check. Users who
  edited their writing rules keep their text; the built-in rules above still
  apply to them.

## Verification

- No Gemini key on this Mac mini, and the MacBook was unreachable. The prompts
  were replayed on `gpt-6-luna` (the OpenAI writing model) through the owner's
  CLIProxyAPI, with the app's developer/user message split and
  `reasoning_effort: none`. The prompts were built by compiling the real
  `PromptV1.swift` and `DictationRulesSeed.swift`. The old prompt was run on
  the same 20 fixtures for comparison.
- Emails with a sign-off, or with two paragraphs: greeting line, blank lines,
  sign-off and name on separate lines in 15 of 15 runs. The old prompt left
  "Hi team," inline, merged the list into prose, and wrote "Cheers,  " with a
  Markdown hard break.
- Greeting with one short line (4 fixtures, 12 runs): stayed inline every run.
  Body-only reply: plain paragraphs, 3 of 3.
- Sentence lists: blank lines between items in 9 of 9 runs; nested
  sub-items stayed tight. Short-item lists stayed tight in 11 of 11 runs.
- Self-correction, question, injection, spoken punctuation: unchanged. The
  validation gate accepted every non-empty answer.
- Not a regression, seen on both prompts: the all-filler take ("um uh yeah
  okay") comes back empty and trips the gate (`empty_output`), and "we need to
  pick up milk eggs bread and butter bullet points" drops "We need to pick
  up" (5 of 6 on the old prompt, 8 of 8 on the new).
- `scripts/test.sh`: 192 tests, 9 skipped, 0 failures. `scripts/build.sh` and
  `scripts/build-ios.sh` succeed.
- Not verified: Gemini 3.8 Flash, and a live dictation in the app.
