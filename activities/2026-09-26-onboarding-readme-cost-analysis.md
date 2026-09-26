# 2026-09-26: onboarding refresh, README rewrite, Cost Analysis

## Why

The onboarding still described the fn/Globe hold gesture after the dictation
key became a single-press toggle, the README still carried the original
author, license, and Releases install steps, and there was no way to see what
the Gemini calls behind each action cost.

## What changed

- Onboarding: the Globe screen is skipped unless the configured key is `fn`;
  the permissions screen adds an optional Screen Recording card; the how-to
  screen lists every configured shortcut; copy mentions spoken lists and
  auto-learned words. `docs/images/icon.png` is the real app icon.
- README: single-press keys table, Setup replaces Install, author/license and
  the Releases download removed, module list and URL routes updated.
- Cost Analysis: new `VoiceIQCore/Sources/Usage/` (TokenUsage, PriceBook,
  UsageStore, UsageMeter), usage read in `GeminiClient.post` and in the live
  session, task-local attribution from the coordinator, retry queue and
  meeting engine, new `CostPane` section, per-dictation cost in History.
  See `docs/COST_TRACKING.md`.

## Decisions

- Prices are the paid-tier Standard figures; the app cannot detect the free
  tier, so the pane says so instead of guessing.
- The live socket's usage frames are treated as per-turn totals (largest
  wins), not summed, to avoid double counting. Estimation from bytes sent
  covers sessions with no usage frame, flagged ≈.
- The ledger lives in its own `usage.sqlite` and is not touched by "delete all
  history".

## Verification

- `swift test --package-path VoiceIQCore`: 193 tests, 9 skipped, 0 failures.
- Release build installed to /Applications; real dictation, Ask Anything and
  Translate runs checked against `log show` usage lines and the Cost pane.
