# 2026-09-26: Prompt comparison with VoiceInk and FluidVoice

## Why

The user asked how Voice IQ compares with VoiceInk and FluidVoice and for the
default system instruction that gets the most out of the app. Both projects are
popular open-source macOS dictation apps with an LLM cleanup step, so their
prompts are the closest public references for ours.

## What changed

Read VoiceInk's `AIPrompts.swift` and FluidVoice's cleanup prompt through the
Librarian. Wrote `docs/design/prompt-comparison-2026-09-26.md` with the feature
table, verdict, and the full effective default prompt (`PromptV1.rules` plus the
`DictationRulesSeed` sections and the wording of each optional section).

Four rules were folded into `PromptV1.rules` from VoiceInk:

- Keep dictated greetings, sign-offs, "please", "thank you", and names; never
  add an unspoken greeting, sign-off, heading, or lead-in.
- Numbers rule now covers percentages, measurements, phone numbers, filenames,
  and paths, with a `₹300` example, keeps small numbers as words, and says
  never to guess an unclear value.
- New paragraph on a new idea, topic, or tone; about three sentences each.
- Vocabulary section calls the spellings authoritative for phonetically close
  mistakes and tells the model not to force a replacement when the speech
  clearly means something else.

Not borrowed: app-based Modes (product decision: intent comes from speech),
window OCR text (we attach screenshots), FluidVoice's JSON transcript envelope
(the `RAW:` fence plus the injection rule already covers it). The single-turn
prompt layout stays; `system_instruction` made no measurable difference in the
earlier probe.

## Verification

Replayed five raw dictations through the revised prompt on `gemini-3.8-flash`
with `.amp/in/callclean.sh` (latency 1.5–2.4 s each):

- raw1, one complaint about formatting: stayed prose, no list invented.
- raw2, long multi-topic request: readable paragraphs, the accept-CTA sentence
  kept, no added lead-in. The model emitted em dashes on its own.
- raw3, hedged status update: "Tomorrow we will connect, or first thing on
  Monday" kept as one sentence.
- raw4, VoiceInk's email example: "Hi Maya, … 1. The printed map 2. Two markers
  3. The spare batteries … Thanks, Alex". "Before Saturday" attached to the
  following sentence; the spoken order is ambiguous, so this is accepted.
- raw5, numbers: "$500 … $35 … ₹300 … 20,000 records in 35 files … two more …
  macOS 26 Tahoe? Please do it."

`swift test --package-path VoiceIQCore`: 209 passed, 9 skipped.
`./scripts/build.sh`: no errors.

Rebuilt the notarized release (`scripts/release.sh`, DMG accepted by
`spctl`) and reinstalled `/Applications/Voice IQ.app` (v0.4.0, build number
unchanged at 9). Changes are committed locally and not pushed.
