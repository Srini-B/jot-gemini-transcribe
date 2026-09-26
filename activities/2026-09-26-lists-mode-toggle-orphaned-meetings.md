# 2026-09-26: Lists on long dictations, mode shortcuts tap only, orphaned meetings

## Why

Three follow-ups from the single-press change.

The user dictates several problems or requests in one long take and expects a
numbered list, the way Typeless formats them. Our cleanup returned paragraphs:
of 24 inserted dictations longer than 60 s, one contained a list. Replaying
eight real raw transcripts over 75 s (150 to 270 words) through the shipped
prompt gave 1 list in 24 runs.

Ask Anything and Translate still had a hold-or-tap split (release after 0.35 s
finalized, a shorter tap locked). The user wants every shortcut to be a tap.

A meeting folder sat in the Meetings list as "0s · Recording" forever because
the process died while it was recording and nothing ever closed it.

## What changed

### Prompt (`PromptV1.swift`)

Text-only replays with three runs per fixture drove each step.

- The intent rule now tells the model to count the separate requests, tasks,
  or reported problems before writing, says a long dictation usually carries
  several even without "first" or "another thing", and that the list changes
  layout only, with every sentence of each item kept. Result: the three
  multi-problem fixtures listed 9 of 9 runs, the five single-topic ones stayed
  prose 15 of 15. One fixture lost 20 percent of its words until the "layout
  only" sentence went in; after it the listed versions were longer than the
  baseline paragraphs.
- Two long examples: a three-paragraph report of three unannounced problems
  that becomes a numbered list, and a two-paragraph report of one problem that
  stays prose. All earlier examples were one or two lines, so long input did
  not resemble any of them.
- The paragraph rule says paragraph breaks in RAW are the recognizer's guesses,
  not the speaker's structure.
- With the recording attached (what the app sends) the same prompt lost the
  list on two of three fixtures. A one-paragraph layout reminder placed
  directly before `RAW:` fixed that, but a first wording over-listed: a status
  update to a colleague, a short chat, and a leading question all became list
  items. The final wording names those exceptions. Text replays then matched
  the expected layout on all 16 fixtures, three runs each; audio replays 20 of
  21 (the miss is the fixture whose second problem is only loosely separated
  from the first).

`thinkingLevel` stays `low`; the fix did not need more thinking time.
Latency in the replays was 2 to 5 s.

### Mode shortcuts (`DictationController.toggleModeShortcut`)

One press starts a hands-free Ask Anything or Translate session, the next
press of the same shortcut or of the dictation key ends it, release does
nothing. `shortcutDownAt` and the 0.35 s threshold are gone. Onboarding copy
says "Press" instead of "Hold".

### Orphaned meetings (`MeetingEngine.failInterruptedRecordings`)

At launch, any meeting still marked `.recording` is set to
`.failed("interrupted")` with an end time, so the list shows "Failed" and the
row can be deleted. The one stale folder from today was deleted by hand.

## Verification

- `swift test --package-path VoiceIQCore`: 193 tests, 9 skipped, 0 failures.
- `./scripts/build.sh` clean.
- Replay tooling under `.amp/in/`: `bench.sh <name> [level] [runs]` over
  `.amp/in/long/L*.raw.txt` (real raw transcripts pulled from history.sqlite)
  and, with `FIX`/`FIXOUT`, over the nine short fixtures; `audioA.sh` and
  `audioRe.sh` replay a recording folder through the app's RAW+audio prompt.
  Outputs are in `.amp/in/long/<name>/` and `.amp/in/aud*.A*.txt`.
- Release build installed to `/Applications/Voice IQ.app`. A live spoken
  multi-problem dictation was not run in this session; the user should try one.
