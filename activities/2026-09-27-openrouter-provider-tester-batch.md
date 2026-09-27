# 2026-09-27 — OpenRouter provider and the first tester batch

## Why

The AI Studio key sits on Tier 1, and the 12-minute dictation incident
(`2026-09-27-rate-limited-long-dictation-retry.md`) showed the per-minute audio
token limit cannot be worked around on that tier. Raising the tier needs weeks
of spend. OpenRouter serves the same Gemini models per call with no tier gate,
so it is offered as a second provider rather than a replacement.

A first external tester also reported seven issues from the shared DMG, worked
through below.

## OpenRouter

`ModelProvider` (`gemini` / `openRouter`) plus `SettingsStore.preferredProvider`
and `activeProvider`. Both keys stored → the Advanced pane shows a Provider
picker; one key → that key is used; no key → Gemini. `GeminiClient` gained
`openRouterKey` and `provider` closures and routes every call when OpenRouter is
active; `GeminiClient+OpenRouter.swift` holds the two request builders and the
response parsers. The shared `post` got a `via:` argument so the status → error
mapping stays in one place (402 added as a retryable "insufficient credits").
`TokenUsage.fromOpenRouter` reads the OpenAI-shaped usage plus `cost`;
`UsageRecord` prefers that reported cost over `PriceBook`.

Decisions:

- Live transcription stays Gemini-only. OpenRouter has no WebSocket surface,
  and a live path that silently degrades is worse than none, so the live
  factories return nil while OpenRouter is active.
- OpenRouter's `/audio/transcriptions` has no smart mode, custom vocabulary or
  diarization. Dictation still gets the dictionary through the cleanup pass;
  meetings get one unlabelled speaker.
- Onboarding keeps asking for a Gemini key. OpenRouter is an Advanced option
  for people who already hit the limit.

Verified without an OpenRouter key on this machine: `google/gemini-3.5-transcribe`
is listed under `/api/v1/models?output_modalities=transcription` and
`google/gemini-3.8-flash` under `/api/v1/models`; `/audio/transcriptions` and
`/key` answer 401 with the documented error envelope for a missing or bad key.
A real transcription through OpenRouter has not been run yet. Core tests: 193
passed.

## Tester batch

1. **Gatekeeper.** Tester got "Application cannot be opened" from the DMG and
   the zip until `xattr -cr`. Reproduction attempt on the Mac mini (macOS
   26.6.2, assessments enabled): the new DMG and zip were given a Safari
   quarantine attribute, mounted / extracted, and `spctl -a -t exec` accepted
   both copies as "Notarized Developer ID"; `stapler validate` passed; the
   quarantined app launched. `scripts/release.sh` staples the app, re-zips it,
   then signs, notarizes and staples the DMG. The report could not be
   reproduced with the current pipeline; the exact dialog text and
   `spctl -a -t exec -vv` output from the tester's machine are needed.
2. **Ask Anything latency.** `WebContext` per-page limit 3 000 characters and
   a 4 s fetch budget; sources always on their own paragraph; answer rendered
   full-width by `RichTextView`.
3. **Cost pane.** Simple view by default (totals and by-action calls/cost), a
   Detailed switch adds token columns, by-model and recent calls. Footer text
   comes from `ModelProvider.pricingNote`. The $0.01 for "Hello, hello, how are
   you?" is the paid-tier price of a transcribe call plus a flash cleanup with
   audio and screenshots attached (about $0.009); the arithmetic was checked
   against the pricing page.
4. **Live transcript freeze.** `LiveTranscriptionSession.rollActivity()` now
   waits (up to 2.5 s) for the server's `generationComplete` of the closed turn
   before sending `activityStart`; sending it immediately made the next turn
   return no partials and no final (measured: 2 finals for 3 turns on a 150 s
   dictation). Verification result recorded below.
5. **Pill anchors.** Five snap positions along the bottom edge, drag grip on
   the pill and on the answer card, persisted in `pillAnchor`. The first grip
   was an `NSViewRepresentable`; on macOS 26 it never received `mouseDown`
   under the Liquid Glass capsule (synthetic drags moved the window only via
   the AppKit background drag, while the SwiftUI stop button next to it took
   clicks). Rewritten as a SwiftUI view with a `DragGesture` that posts
   notifications; `PillHUDController` follows the mouse and snaps on release.
6. **Meetings.** Summary in the dominant spoken language; transcript view is
   one `RichTextView` instead of per-word views (a 20-minute transcript froze
   the window); green tick when notes are ready. Two gaps found while
   verifying: `MeetingEngine.retry(id:)` existed but nothing called it, so a
   failed meeting could never be retried, and a 30-minute meeting failed on
   its second chunk with a 429 because chunk 1 goes out right after a
   25-minute chunk 0. Added a Retry toolbar button (failed meetings only,
   idle engine only) and a per-chunk rate-limit wait (`Retry-After` + 2 s,
   capped at 65 s, twice per chunk). Retry re-transcribes every chunk; a
   per-chunk cache was not added.

## Verification

Installed Developer ID release build, 2026-09-27.

- Live transcript: 161 s dictation, three activity turns, 3 finals for 3
  turns, 1 974 characters of partials with no frozen span. Before the fix the
  same length gave 2 finals for 3 turns.
- Cost pane: simple view (totals, by action) and Detailed view (token columns,
  by model, recent calls) both screenshotted; toggle persists.
- Pill anchors: synthetic drags from the centre anchor snapped to X = 0, 340,
  980, 1620 and 1960 on the 2 560-wide display; `pillAnchor` persisted and
  the pill sits flush at the edges.
- Meeting retry: the failed Tamil Meet meeting (30 m, `rateLimitedTransient`)
  retried from the new button; chunk 0 transcribed ($0.107), chunk 1 was rate
  limited twice (waited 28 s, then 56 s) and then transcribed ($0.025); notes
  ($0.003) came back with a Tamil title and summary. The 88-entry transcript
  scrolls top to bottom without a stall.
- Gatekeeper: not reproducible on the Mac mini with quarantined DMG and zip.
- OpenRouter: no key on this machine; end-to-end transcription still unrun.
- Core tests and app build: recorded below.
