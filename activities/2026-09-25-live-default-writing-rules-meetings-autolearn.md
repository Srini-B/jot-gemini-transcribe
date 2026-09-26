# 2026-09-25 — Live default, writing rules, no recording cap, auto-learn, meeting notes

## Why

The fork needed the upstream live-transcription PR and four user-facing gaps
closed: mid-dictation instructions and run-on speech were pasted as heard,
the 10-minute cap cut recordings off and pasted the live text without the
rules pass, corrections typed after insertion were never learned, and calls
were not recorded or summarised. Constraints from the owner: Swift, macOS,
Gemini only, no local models, defaults that need no settings changes.

## What changed

- Merged upstream PR #12 (fast-forward to `cd6fe60`): `gemini-3.5-transcribe-live`
  is the default path, batch `gemini-3.5-transcribe` remains the fallback.
- Writing-rules pass (`smartCleanupPass`) on by default, `gemini-3.8-flash`,
  with a user-editable custom-instructions block seeded from the owner's
  `dictation-rules.md`. One-shot migration enables it for existing installs
  unless Smart transcription was explicitly off. Live results now go through
  the same pass before insertion.
- Recording cap removed. Past 9:30 the live socket is abandoned; `AudioChunker`
  splits long CAFs at ≤10 min on silence and each chunk is transcribed.
- Auto-learn: `EditLearner` watches the inserted field over AX for 10 min,
  remembers up to 20 insertions per field for 2 h so edits to earlier sessions
  in the same field are still learned, and writes 1–3 word corrections into the
  Dictionary as `source: .auto`.
- Meeting notes: `CallDetector` + `MeetingEngine` record mic and system audio
  (Core Audio process tap), diarised transcript through Gemini, summary and
  action items from `gemini-3.8-flash`, Settings → Meetings pane.
- `CallDetector` rewritten late in the session: the first version used the
  global "mic in use" bit, so Jot's own meeting tap kept the call "active"
  and a dictation with Zoom idle in the background would have started a
  recording. It now reads per-process input activity
  (`kAudioHardwarePropertyProcessObjectList`, macOS 14.2+) and maps browser
  helper processes back to the browser.

## Decisions to revisit

- `gemini-3.8-flash` for cleanup and meeting summaries (newest flash model in
  the docs at the time; pinned in `GeminiClient.init`, overridable in Advanced).
- Live path abandoned at 570 s rather than reconnecting; batch handles the rest.
- Cleanup deadline formula 3 s + 1 s per 350 characters, max 60 s. Untuned guess.
- Auto-learn limits (20 insertions, 2 h, 1–3 word diffs) are heuristics.
- Diarisation without timestamps; speaker labels restart per 25-minute chunk.
- Pre-14.2 fallback in `CallDetector` uses the global mic bit, so there a call
  ends only when the app quits or the tab closes.

## Verification

- `swift build --package-path JotCore`: clean (pre-existing Swift 6 warnings).
- `swift test --package-path JotCore`: 209 tests, 9 skipped, 0 failures
  (same as baseline before this work).
- `./scripts/build.sh`: app builds.
- `AudioChunker` exercised with a throwaway XCTest on a 25-minute synthetic
  CAF: 3 chunks, cut moved onto silence at 595.0 s, fallback cut at 1190.6 s
  when no silence in window. Test deleted afterwards.
- Core Audio per-process input query probed with a scratch binary on this
  Mac: 29 process objects enumerated with bundle IDs and `IsRunningInput`
  flags; `responsibility_get_pid_responsible_for_pid` resolved a
  `com.apple.WebKit.GPU` helper to its owning app.
- 2026-09-26: Settings → Dictation and Settings → Meetings rendered and
  screenshot-inspected in the debug app.
- 2026-09-26: three manual meetings recorded in the debug app with two `say`
  voices routed through the system tap. Final run: mic.caf 18.08 s, system.caf
  18.26 s, wall ≈ 18 s; transcript had 4 turns with `spk:0`/`spk:1` correctly
  alternating; notes had a title, summary, and 3 action items with deadlines
  and one owner.

## Incidents fixed on 2026-09-26

- Diarization returned one glued text block and no speaker annotations until
  `timestamp_granularities: ["word"]` was added to the transcription mode
  (verified against the live interactions API, then in-app).
- `MicTap` built on `AVAudioEngine` wrote 44.9 s for a 77.6 s meeting when
  started before the system tap, and wrote zero frames when started after it,
  while standalone probes with the same order captured fully. Replaced with a
  Core Audio IOProc on the default input device plus a default-input listener.
  Start order is now system tap, then mic.

## Gaps

- Automatic call detection (`CallDetector`) not exercised against a real
  call; meetings were started manually.
- AX-based auto-learn not run end to end against a real text field.
- Cleanup quality against the live API not evaluated.
- Typeless inventory done from the unpacked bundle
  (`.amp/in/typeless/TYPELESS_V2.8.0_INVENTORY.md`, untracked); feature gaps
  it exposed are listed there and not yet implemented.

## Delivery state

All work is uncommitted in the working tree on `main`. Nothing pushed, no PR.
