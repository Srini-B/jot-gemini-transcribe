# Sarvam Saaras V4, rupee costs, and the ⌘-Tab abort

2026-10-03. Local, uncommitted at the time of writing.

## Why

Sarvam released Saaras V4 (speech-to-text for 22 Indian languages and English)
and prices it in rupees. The request: add it as a fourth transcription
provider, use Sarvam's text model for the writing pass, show costs in rupees as
well as dollars, and fix a dictation that cancels itself when the user
switches apps right after the hotkey.

## What was found before building

- Saaras V4 is speech-to-text only. The writing pass needs a chat model;
  Sarvam offers `sarvam-105b` on an OpenAI-shaped `/v1/chat/completions`.
  It takes text only, so the screenshot never reaches Sarvam. Gemini and the
  other providers keep theirs.
- `language_code=unknown` auto-detects and reports `language_probability`,
  so the Language picker defaults to "Detect automatically"; the 23 languages
  are there for when detection misses.
- The sync endpoint stops at 30 s. Longer audio and every diarized request go
  through the batch job flow (create → upload to Azure → start → poll →
  download). Diarization returns speaker turns, not words.
- Prices (docs, 2026-10-03): STT ₹30/hour, ₹45/hour with diarization;
  `sarvam-105b` ₹29.28 in, ₹10.98 cached, ₹73.20 out per million tokens.
- Translate, transliterate and language-id text APIs exist. Not built: the
  app has no place for them yet.

## Decisions

- The USD→INR rate comes from Frankfurter (ECB reference rate, free, no key).
  Each usage row stores the rate and the ECB date it came from, taken when the
  call is booked. A row booked without a rate (offline, or the cache older
  than 36 h) is back-filled later at its own day's rate, never at today's.
  Weekends and holidays use the last published day.
- Rupee costs are derived (`costUSD × fxRateINR`), not stored twice. A Sarvam
  row's rupee figure therefore equals the list price exactly (20 s → ₹0.1667).
- Historical rows were back-filled at each day's rate; the Cost pane's USD/INR
  toggle covers all history.
- Transcription provider: segmented control → menu, on Mac and iOS.
- Meetings on Sarvam use the diarized batch job; speaker turns feed the same
  `DiarizedWord` path the OpenAI diarizer uses.

## Follow-up: iOS parity and the writing-model default

- Picking Sarvam as transcription provider now defaults the writing model to
  Sarvam 105B. `SettingsStore.preferredWritingSource` derives the default from
  the transcription source when no `writingSource` key is stored; a stored
  choice wins whatever transcribes. The pickers show the derived value without
  writing it, so switching back to another provider restores the provider's
  model unless the user chose one.
- iOS Cost page gained the USD/INR toggle (same `costPaneCurrency` key) and the
  rupee footer; `AppModel` refreshes the rate and back-fills unrated rows at
  launch like the Mac controller. Compile-checked only; no simulator run.

## The ⌘-Tab abort

Report: tap the hotkey, switch apps within a second, dictation cancels. Code:
`EventTapEngine` fed every key-down inside the first second to the
accidental-chord abort. ⌘-Tab's Tab is such a key-down. Fix: only a key
pressed while the trigger modifier is still held counts as a chord. A key
after the release passes through and the session stays.

Reproduction on the installed build was blocked: a bare `fn` press cannot be
posted from this session (TCC denies the SSH process Accessibility, and
cua-driver posts to a pid, which the session tap does not see). The mechanism
is verified from code only. Manual check: tap `fn`, ⌘-Tab at once, speak, tap
`fn` again; the text should arrive in the second app.

## Bug found while verifying

The batch job-create call answers `202 Accepted`. The shared `post` treated
any non-200 as a transient network error and retried, so every dictation over
30 s on Sarvam (and every Sarvam meeting) queued forever. `post` now accepts a
2xx from Sarvam. The sync path was unaffected.

## Verification (installed, notarized 0.5.12 build)

- 148 core tests pass; Debug and iOS builds compile.
- 20 s recovered dictation on Sarvam: sync call 621 ms, language `en-IN`
  (p=1.00), transcript correct, usage row $0.00173 with rate 96.32 dated
  2026-10-02 (Saturday → last ECB day).
- Cost pane: USD and INR agree (₹3.20 = $0.0333 × 96.32); the Sarvam tab shows
  ₹0.1667 for the 20 s call. Historical rows carry their own day's rate
  (10-01 → 96.33, 10-02 → 96.32).
- Key validation, provider menu, language picker and writing-model picker
  checked on screen.
- After the 202 fix, rebuilt, notarized and reinstalled: an 81 s recovered
  dictation went through the batch job (about 5 s) and `sarvam-105b` cleanup;
  usage $0.00701 (= ₹0.675). A seeded two-speaker meeting (mic.caf and
  system.caf from two `say` voices, 32 s) came back as four turns, s1/s2 at
  the right boundaries, notes and action items from `sarvam-105b`; usage
  booked at ₹45/hour.
- Rows and recordings from these checks remain in History, Meetings and the
  usage database on the Mac mini. Delete them from the app if unwanted.

## Not done

- Translate, transliterate and language-id APIs (reported, no UI).
- Hotkey fix: code-level only; see above for the manual check.
