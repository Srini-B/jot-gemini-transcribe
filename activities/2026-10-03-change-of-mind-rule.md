# Writing rules: a change of mind replaces what it reverses

2026-10-03. Released in 0.5.12 (37).

## Why

A 6.5-minute MacBook dictation into Slack (2026-10-02 21:30, transcribed by an
experimental WhisperKit build, cleaned by `gpt-6-luna` at reasoning `none`)
ended with the speaker reversing a decision twice: "there shouldn't be an
option to select only … you know what, let it be there, let the user choose …
no, I changed my mind, don't provide the option …". The output kept "You know
what, let it be there … No, I changed my mind." The transcript was accurate;
the writing pass did not remove the abandoned positions.

The rules already said changes of mind never appear, but only in the opening
paragraph. No rule or example covered a position that is stated, reversed, and
reversed again.

## What changed

`PromptV1.rules` gained one rule after the later-corrections rule: write only
the position the speaker ends on, delete each abandoned position with its
change-of-mind words, at any distance, and only when the abandoned position was
spoken in the same dictation. Telling the reader about an earlier decision
("hey Sam, I changed my mind about the venue") and someone else's change of
mind stay. `PromptV1.examples` gained one example (the PDF export option).

## Verification

Replayed the app's exact cleanup prompt (default writing rules, no dictionary)
through the CLIProxyAPI endpoint. Harness: `.amp/in/reveval/` (not committed).

| Fixture | Model | Before | After |
|---|---|---|---|
| The real dictation | gpt-6-luna, `none` | 7/16 clean | 12/12 clean (and 12/12 with an earlier draft of the rule) |
| The real dictation | gpt-6-luna, `low` | 4/8 clean | not needed |
| The real dictation | gemini-3.8-flash-high | 4/4 clean | 4/4 clean |
| 4 short reversals, 1 late back-reference | gpt-6-luna | all pass | all pass |
| 7 controls (reported or past changes of mind, weighing options, "no wait" as content) | gpt-6-luna | all pass | 1 miss in 32 on one control |
| CONTRIBUTING set (self-correction, list, question, spoken punctuation, all-filler, injection) | gpt-6-luna, gemini | all pass | all pass |

In every passing run of the real dictation, the final position was kept. Most
runs moved it into the earlier point that first raised the topic. The
ValidationGate accepted all 16 outputs it was given. `scripts/test.sh`: 148
tests pass.

The one control miss shortened "not sure, Friday or Monday, Friday gives QA
less time, Monday is safer, let's go with Monday" to "Let's go with Monday."
once in 32 runs; the base prompt kept the reasoning in 36 of 36 runs.

Raising Luna's reasoning effort to `low` did not help (4/8), so the effort
stays `none`.
