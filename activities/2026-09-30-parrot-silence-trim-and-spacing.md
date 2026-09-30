# 2026-09-30: Silence trimming and spacing, borrowed from Parrot

## Why

The owner asked what VoiceiQ can learn from Parrot (humanitas-labs/parrot,
MIT, a local-Whisper push-to-talk app with no LLM pass). Parrot has nothing
to teach about formatting. Its insertion and audio handling does. The owner
accepted silence trimming, the spacing rules, and the vocabulary ideas. He
declined the focused-field check.

## What changed

- `AudioChunker.speechRange` trims leading and trailing silence before any
  upload. It is Parrot's `SilenceTrimmer` rebuilt over the CAF: 10 ms frames,
  a frame is voiced above max(0.003 full scale, 5% of the loud level), and it
  keeps 250 ms of audio before the first voiced frame and 350 ms after the
  last. One change from Parrot: the loud level is the fifth-loudest frame, not
  the loudest, so a 20 ms key click cannot raise the bar above quiet speech.
  Parrot pads 300 ms of synthetic silence for local Whisper; the cloud models
  do not need that, and the margins are real audio. `ranges(cafURL:)` chunks
  inside the trimmed range and now also returns the file length, so each
  chunk's seconds (and ElevenLabs' billed seconds) count only what is sent.
  `polish` attaches the trimmed range too. The saved CAF is not changed.
- `AXInserter.joined` adds no leading space after `@`, `#`, `<`, `«`, `‹`,
  `¿`, `¡`, or before `…`, `%`, `”`, `’`, `»`, `›`, or when either side is
  Chinese, Japanese or Thai. These are Parrot's character sets.

## Not done

- Vocabulary. Parrot's two lessons are about local Whisper's prompt tokens: a
  natural sentence works where a bare word list is ignored, and a
  wrong-language prompt pulls the transcript into that language. Our providers
  take vocabulary through fields designed for word lists (Gemini
  `custom_vocabulary`, gpt-transcribe `keywords[]`, ElevenLabs `keyterms`).
  OpenAI's own guide gives whisper-1 a comma-separated list, not a sentence.
  The language lesson maps to gpt-transcribe's `languages[]` and similar
  fields, which need to know which languages the user speaks. That would be
  a new setting, so it is the owner's call. The whisper-1 SECOND still gets
  no prompt; that was a deliberate choice on 2026-09-28, and no OpenAI key
  was available to measure a change.
- The focused-field check. The owner wants dictation to paste wherever the
  cursor is. Today `InsertionCoordinator` still copies instead of pasting
  when the frontmost app changed. That is left for the owner to decide.

## Verification

- 232 real recordings from the MacBook (3.66 h). The trim cut 3.1% of the
  audio. 150 recordings were not trimmed at all. The largest cuts were 34 s
  at the start and 63 s at the end.
- The 97 stretches cut from 61 recordings were transcribed with
  `whisper-large-v3-turbo` (mlx-whisper on the Mac mini). Every one gave only
  silence hallucinations ("Thank you.", "you", "I'm going to go to the next
  video."); none held a word of the dictation's transcript. Seven recordings
  whose kept edges looked suspicious in a 4 s check were checked again with
  12 s windows. The full and trimmed edges gave the same words in all seven.
- The fifth-loudest rule changed the cut on 20 of 232 recordings compared
  with Parrot's loudest frame, always toward keeping more audio.
- Throwaway XCTests, deleted afterwards. A synthetic CAF (2 s noise, a 20 ms
  full-scale click, 2 s noise, `say` speech, 3 s noise) went through
  `AudioChunker.ranges` and `FLACEncoder`: 8.8 s in, 4.4 s encoded, with the
  speech and the click kept. `AXInserter.joined` gave "你好我们明天见",
  "ping @rohan", "tag #release", "5% higher", "done. Next" and "it's fine".
- `scripts/test.sh`: 192 tests, 9 skipped, 0 failures. `scripts/build.sh`
  and `scripts/build-ios.sh` succeed.
- Not verified: a live dictation against a real provider. No model key was
  readable on the Mac mini or the MacBook.
