# 2026-09-28: History Retry on a finished dictation did nothing

## Report

- MacBook, 20:48, a 77 s dictation into WhatsApp on OpenAI
  (`gpt-transcribe+gpt-6-luna`). Raw transcript opened "But stop the other
  things. Look, find to me." for what was said as "(The) rest of the other
  things look fine to me." Retry Transcription in History did nothing.

## Findings

- Retry: `RetryQueue.retrySingle` skipped any dictation whose status was
  `inserted`, `awaitingChip` or `recovered` and returned `.alreadyDone`, which
  the Mac handled with no notice. So Retry only worked on failed or queued
  rows, and on everything else it silently did nothing.
- The first sentence: the audio is quiet for about 2 s and speech starts
  right away. Sent to OpenAI again from the Mac mini as the app sends it
  (FLAC, the MacBook's 91 dictionary words as `keywords[]`), `gpt-transcribe`
  got it right in 6 of 6 runs in one batch and 3 of 4 or 4 of 5 in others;
  the wrong reading came back each other time, word for word, including with
  `temperature=0`. Without keywords it was wrong in 6 of 6
  ("Instead of the other things, look, find to me."); with `language=en` 3 of
  3 wrong; `chunking_strategy=auto` 1 of 6 right. `whisper-1` got it right on
  the first 15 s; `gpt-4o-transcribe` dropped the sentence. So the model is
  uncertain on this opening; a second attempt usually fixes it, which is what
  Retry is for.

## Change

- `retrySingle` transcribes again even a finished dictation (`process(again:)`).
  On success the new raw and cleaned text replace the old; the status stays
  (it was delivered). On any failure the earlier text is kept. The background
  drain still leaves finished dictations alone. With the audio already purged,
  Retry reports failure and keeps the text.
- Mac: "Transcribing again…" while it runs, then "Transcribed again — the new
  text is in History", or "Couldn't transcribe it again — the earlier text is
  kept". An open History detail sheet refreshes to the new text
  (`HistoryStore.record(id:)`).
- Verified with a throwaway XCTest (stub transcriber, deleted): offline keeps
  the text and status; success replaces the text and keeps `inserted`; a
  drain afterwards changes nothing. `scripts/test.sh` 192/0; Mac and iOS builds
  pass. Not yet on the MacBook (no build installed there this round).

## iPhone Retry and release 0.5.2 (27)

- iPhone History shows "Retry transcription" on every dictation with a
  recording or a transcript, as on the Mac (it was failed and queued only).
  The detail page reloads the record after the retry and says "Transcribed
  again", or that the earlier text is kept. Checked in the Simulator on a
  finished dictation (Gemini through OpenRouter): "Transcribed again".
- Version 0.5.2 (27) for both apps (`project.yml`; build 26 was already on
  TestFlight). iOS: `scripts/release-ios.sh`, on TestFlight in "VoiceiQ
  Internal". macOS: `scripts/release.sh` on the Mac mini, the first Mac release
  built there (Developer ID from the imported identity). App and DMG
  notarized and stapled.
- The DMG's Finder layout step timed out (AppleEvent -1712) and the script
  fell back to the default layout. Finder answered a test script right after,
  so the DMG was rebuilt with `make-dmg.sh` from the stapled app, then signed,
  notarized (Accepted) and stapled again by hand.
- MacBook: the DMG was copied to `~/Downloads`, the app replaced in
  `/Applications` and launched; Gatekeeper reports "Notarized Developer ID".
  On first launch the auto-learn cleanup removed `there's`, `we`, `Learned`
  and `last` (91 → 87 entries); writing rules are on.
