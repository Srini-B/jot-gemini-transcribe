# 2026-09-26: Keep live transcription, write what the speaker meant, quiet meeting rows

## Why

Three requests in one message. Whether live transcription should go, since the
cleanup model gets the recording anyway. Why every finished meeting row says
"Done". And a cleanup output closer to Typeless's "dictate the way you think":
a restatement without a correction word should replace the earlier version, and
naturally spoken parallel points should become a list without list words.

## Live transcription stays

Measured on three real recordings from `~/Library/Application Support/Voice IQ/recordings`
(`.amp/in/audioexp.sh`, ffmpeg to 16 kHz mono FLAC, `gemini-3.8-flash` cleanup at
`thinkingLevel: low`, temperature 0):

| Path | Latency | Quality |
| --- | --- | --- |
| A. Live RAW + FLAC cleanup (current) | 2.9–4.4 s | best; fillers gone, lists kept |
| B. FLAC cleanup, no RAW anchor | 3.1–6.5 s | worse; fillers kept, list structure lost, more verbatim |
| C. Batch `gemini-3.5-transcribe` smart mode alone | 4.9–7.1 s | more verbatim than live smart output |

History DB confirms the same shape: live rows finish the pipeline in 3–4.3 s,
batch-fallback rows in 6–18 s. Dropping live would cost 5–7 s per dictation and
would not make the edit deeper, so live remains the source and the FLAC stays
attached as the word-level authority.

Live RAW can still bias sentence boundaries (E99 had "or first thing on Monday"
where the audio says "have a look at it tomorrow. We will connect first thing
on Monday"). With the revised prompt the F99 replay produced the correct
boundary in 2.8 s.

## Two-part responses were tripping the gate

With a FLAC attached, `gemini-3.8-flash` sometimes returned two text parts: the
first its working ("The speaker says… Let's re-listen at 01:21…"), the second
the answer. Neither carried `thought: true`. `GeminiClient.extractText` joined
every part, so the output was 2.7–3× the raw length, `ValidationGate` rejected
it (`maxLengthRatio` 1.60), and the raw transcript was pasted. Seen in 2 of about
8 audio runs (E99, F188 first run: 17.9 s with a 20 607-character first part).
Three trips in 24 h would have auto-disabled the cleanup pass. `extractText`
now drops `thought` parts and empty texts and returns the last text part.
`defaults read io.blue.voiceiq` showed no `gateTrips`, so the installed app had
not tripped recently.

Thinking level probe on the same recording (`.amp/in/variant.sh`): `minimal` is
rejected by the model, `low` 2.9–6.6 s, `medium` 29–48 s with 9.7k–16k thought
tokens and paragraphs instead of the list, `high` 185 s with 62 911 thought tokens
and an answer part that was itself deliberation. `low` stays. Part order (audio
first or text first) made no consistent difference.

## Prompt stance

`PromptV1.rules` and `DictationRulesSeed.text` now open with "write what the
speaker meant, in their own words" and treat thinking aloud, restarts,
restatements, side notes, and changes of mind as part of the speaking, not the
text. New rules: marker-less restatement keeps only the final version at the
original position, with a guard that a second version naming a different case,
condition, object, or outcome is a separate point (keep both, and when in doubt
keep both); side notes to oneself are dropped and the supplied name or value is
written in place, never invented; two or more parallel points that each carry an
instruction, condition, or option become bullets under the introducing sentence;
closing throwaways such as "that's it" go. Five examples were added to
`PromptV1.examples`. `docs/design/prompt-comparison-2026-09-26.md` was
regenerated from the source (`.amp/in/syncrules.py`).

The user has no stored `customInstructions` override, so the seed edits take
effect directly.

## Meeting rows

`MeetingsPane` rows show the length alone when a meeting is done and add a
label only while recording, transcribing, making notes, or after a failure.

## Verification

- Text replays, `zsh .amp/in/callclean.sh .amp/in/rawN.txt PREFIX`, 1.7–2.0 s
  each: raw6 (implicit restatement of hover behaviour) collapsed to the final
  version; raw7 ("I forget her name… Anita right") became "Can you ping Anita
  from the printing company about the delivery date, and also confirm the
  quantity is still 400?"; raw8 (three "if the token…" conditions) became an
  intro line plus three bullets; raw9 (PR review prose) stayed prose; raw3
  first over-collapsed two observations and the "different case" guard fixed it;
  raw1, raw4, raw5 unchanged from before.
- Audio replays: F99 correct boundary and paragraphs in 2.8 s. F188 (three
  reported problems) produced a numbered list in one run and paragraphs in five;
  list formatting on a long multi-problem dictation is nondeterministic at `low`.
  The mid-sentence "just background fan noise, that's it" was kept, which is
  right; the closing-filler clause targets a trailing "that's it" only.
- `swift test --package-path VoiceIQCore`: 209 tests, 9 skipped, 0 failures.
- `./scripts/build.sh` clean.
- Release build, install to `/Applications/Voice IQ.app`, Meetings list inspected
  for rows without "Done".
