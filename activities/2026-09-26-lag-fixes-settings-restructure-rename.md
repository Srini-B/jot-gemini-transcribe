# 2026-09-26: Lag root cause, settings restructure, module rename

Fourth wave of the day; follows `2026-09-26-tinyfish-web-context-and-fixes.md`.

## Why

- The whole app stalled: the second dictation after launch took ~10 s to
  start, the live pill lagged, the tray menu would not open, hovering the
  sidebar showed the system spinner, and Quit was delayed.
- The General pane held three controls; the user asked for it to go and
  for permission status to live in Settings instead of only in the tray
  menu after a revoke.
- Panes had drifted apart in font weight, header shape, and padding.
- The pill kept showing the live correction overlay after the key was
  released; the user wants bars plus "Still working…" only.
- The dictation key did not stop an Ask Anything or Translate session.
- Long list-style dictations came out as prose paragraphs.
- "Jot" survived in module, folder, project, and identifier names.

## Root cause of the lag

Main-thread work, not the network. Three sources measured with
`ps -M` (main-thread utime) and xctrace:

1. `EditLearner` harvested the target field through AX on the main actor
   after every insertion and every poll (1 s cadence), then ran a
   quadratic diff over the whole field text. With a few sessions in one
   field the diff alone took seconds per poll.
2. `CallDetector` polled AX and Core Audio process objects every 5 s on
   the main actor, with no AX messaging timeout; a hung browser helper
   blocked the run loop for the default 6 s.
3. `PillModel.level` was `@Published` at 30 Hz, so every meter sample
   rebuilt `PillView`; `StatusItemController` redrew the status image at
   the same rate.

## What changed

- `EditLearner`: AX read plus diff run in a detached utility task, only
  the dictionary write returns to the main actor; skip when the field
  hash is unchanged, a harvest is in flight, or the field exceeds 200 000
  characters. `EditDiff.locateWindows` uses interned word IDs, a
  sliding-window hit prefilter, and one Levenshtein table per candidate
  start with early abort, bounded to 24 candidates.
- `CallDetector`: reads run detached with a 1 s AX messaging timeout.
- `PillModel.level` is a `LevelSource` read inside `WaveformView`'s
  `TimelineView`/`Canvas`; the status item sets its template image once
  and pulses `alphaValue` at 15 Hz. `CorrectionView`/`GeminiSweep`
  removed; after release the pill shows bars and "Still working…".
- Settings: General pane removed. `DictationKeySection` (modifier press
  recorder, reset to fn, double-tap toggle) and `PermissionsSection`
  (Accessibility, Screen Recording, Microphone; 1 s poll; each row opens
  the matching System Settings pane) sit at the top of Dictation;
  launch-at-login is the first row of Privacy & Storage.
  `voiceiq://settings/<section>` defaults to `dictation`.
- Pane uniformity: Dictionary's toolbar `.searchable` replaced with the
  same in-pane search row History uses (the toolbar variant restyled the
  titlebar and shifted the sidebar). Advanced and TinyFish fields use
  `LabeledContent` with system-font labels and code font only on values.
  Meetings uses `VoiceIQUI.TypeScale`/`Spacing`. The sidebar separator is
  a 1-pt `Rectangle` that ignores the top safe area so it reaches the
  titlebar.
- Dictation key ends mode sessions: `DictationController.start()`
  intercepts `.begin` while `shortcutMode` is set and finalizes. First
  live test still logged "begin ignored": `transition(to:)` cleared
  `shortcutMode` on `.idle`, and the coordinator re-publishes `.idle` at
  the start of every begin, delivered by the `receive(on: .main)` sink
  after `handleModeShortcutDown` had set the mode. Now only terminal
  states clear it.
- Custom instructions looked ignored for a second reason found in the
  live test: `cleanup unavailable (timeout) — inserting raw`. The cleanup
  deadline floor was 3 s; the full prompt on gemini-3.8-flash measured
  1.7–4.9 s for a one-line transcript (curl, same body, with and without a
  screenshot). Floor raised to 12 s (`cleanupDeadline(forCharacters:)`).
  This also explains the earlier report that the 10-minute cut-off pasted
  "instantly": that paste was the raw fallback.
- A silent clip makes the interactions API return `completed` with no
  `steps` key; `extractInteractionText` threw `network("no_steps")` and
  the pill showed a network failure for silence. It now returns "" so the
  existing silence path handles it.
- `AXInserter.joined` prepends one space when the caret follows a
  non-space character, so a second dictation into the same field no
  longer produces "button.Please".
- `PromptV1` list rule: announced sets ("the first thing… the next
  thing… and also") become one item per line with nested sub-points;
  in-sentence sequences stay prose. New nested-list example. Matching
  rule in `DictationRulesSeed`.
- Web context recency: `webSearchQueryPrompt` asks for a `RECENT:` prefix
  on time-sensitive queries; `WebContext.gather` passes
  `recency_minutes: 10080` and falls back to unfiltered search when the
  recent set is empty.
- Rename: `JotCore` → `VoiceIQCore` (tests `VoiceIQCoreTests`),
  `JotUI`/`JotMotion`/`JotApp` → `VoiceIQ*`, `App/VoiceIQ.entitlements`,
  `project.yml` target `VoiceIQ`, `VoiceIQ.xcodeproj` (generated,
  ignored), scripts and CI `-scheme VoiceIQ`, `com.ammaar.jot.*` →
  `io.blue.voiceiq.*`, notification names `voiceIQ…Changed`,
  `voiceiq-dictionary.csv`, `voiceiq-meeting-`, `voiceiq-notary`,
  `.config/voiceiq/apikey.dev`. Deleted `JotLinks.swift` (no callers) and
  `scripts/make-icon.swift`. Kept on purpose: `KeychainStore.legacyService
  = "com.ammaar.jot"` and the `FileLayout` `Jot` folder move (migration),
  historical docs and activity entries.

## Decisions

- Off-main harvesting over a smaller poll window: the user wants edits to
  earlier sessions in the same field learned, so the window stays 10 min
  and 20 insertions; the cost moved off the main thread instead.
- Kept `.idle` as the coordinator's reset state and fixed the consumer,
  rather than removing the re-publish, so state-table tests stay valid.
- No new tests written (not requested). Rename verified by build and the
  existing suite.

## Verification

- `swift test --package-path VoiceIQCore`: 209 tests, 9 skipped, 0
  failures after rename and prompt edits.
- `./scripts/build.sh`: 0 errors. `./scripts/release.sh`: notarized
  v0.4.0 build 9 signed with Developer ID G8K3545FJ2, installed to
  `/Applications/Voice IQ.app`.
- Pane contact sheet `.amp/in/artifacts/panes-sheet2.png`: shared header
  shape, sidebar separator reaches the titlebar, no toolbar search field.
- Custom instructions path: `customInstructions` key absent →
  `DictationRulesSeed.text` in use; no "cleanup gate REJECTED" warnings in
  8 h of logs, so the list problem was prompt bias, not the gate.
- Dictation key ending a mode session (installed release): Ask Anything
  started via ⌃⌥A, right Option tap → log "dictation key ends mode
  session" → finalizing.
- Lag (installed release, TextEdit target): Ask Anything, then two
  dictations back to back. Hotkey → `warming` in 165 ms and 205 ms,
  second dictation transcribed and inserted in 3 s, main-thread utime
  0.68 s after three sessions, tray and settings responsive.
- List dictation ("The first thing… The next thing… two parts… And
  also…") through the cleanup prompt returned a numbered list with nested
  sub-points (curl against gemini-3.8-flash with the exact prompt).

## Gaps

- `AXInserter.joined` and the raised deadline were verified by build and
  the existing suite plus one live dictation after the rebuild; the paste
  tier still cannot add the joining space.
- Tests with `say` need `muteOtherAudioWhileDictating` off (default on),
  otherwise the recording is silent.

## Delivery state

Committed locally on `main`; not pushed.
