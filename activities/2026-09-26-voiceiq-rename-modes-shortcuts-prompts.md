# 2026-09-26: Voice IQ rename, onboarding fix, Typeless-gap features, default prompts

## Why

- The onboarding wizard appeared on every launch. Root cause: `project.yml`
  signed Debug builds ad-hoc, so each rebuild had a new code signature and
  macOS dropped the Accessibility and microphone grants, which
  `needsOnboarding` treated as a fresh install.
- The Typeless inventory (`.amp/in/typeless/TYPELESS_V2.8.0_INVENTORY.md`)
  listed features this app lacked. The user asked for all of them with
  editable shortcuts, ⌘⇧V for paste-last.
- Custom writing rules are optional, so the built-in dictation and meeting
  prompts had to carry the same detail on their own.
- Product renamed to Voice IQ with the brand sparkle assets.

## What changed

- `scripts/build.sh` signs Debug with the first "Apple Development" identity
  (`security find-identity`), derives the team from the certificate OU, and
  passes `CODE_SIGN_IDENTITY`/`CODE_SIGN_STYLE=Manual`/`DEVELOPMENT_TEAM`.
  `SIGN_IDENTITY=-` restores ad-hoc. `needsOnboarding` no longer re-presents
  a completed wizard; missing permissions go through the attention state.
- Rename: `PRODUCT_NAME` and display name "Voice IQ", `VoiceIQ.icns`,
  `MenuBarIcon(@2x).png` template glyph with alpha-pulse states in
  `StatusItemController`, user-visible strings across the app, README, and
  docs. Bundle ID, `jot://`, module and storage names unchanged on purpose.
  `scripts/make-icons.swift` regenerates the assets.
- Dictation modes (Ask Anything, Translate), side-aware CGEventTap shortcut recorders
  (⌘⇧V, ⌃⌥A, ⌃⌥T), `AudioOutputMute`, microphone preference with new-device
  notice, translation target language. Details in
  `docs/design/architecture.md` (Post-plan additions) and `docs/PRIVACY.md`
  item 5.
- `PromptV1.rules`/`examples` rewritten (4.2 k + 1.9 k characters, 14
  examples). `summarizeMeeting` prompt rewritten with the same JSON shape.
- Dictionary CSV import/export already existed (`DictionaryView.swift`,
  `DictionaryStore.swift`); nothing added.

## FluidVoice comparison (altic-dev/FluidVoice)

Same onboarding diagnosis: it keeps an `onboardingCompleted` flag separate
from live permission checks. It pauses media instead of muting, has a mic
priority list, opt-in paste-last shortcut, no first-class translation mode.
We took the separate-flag idea and the mic preference; kept mute over pause
because Typeless mutes and mute covers every player.

## Verification

- `swift test --package-path JotCore`: 209 tests, 9 skipped, 0 failures.
- `./scripts/build.sh`: 0 errors, signed with the Apple Development identity
  (`codesign -dv` shows TeamIdentifier 9ZVQ96RV4Q).
- Menu bar shows the sparkle template icon; About pane shows "Voice IQ" and
  the new icon; Dictation pane shows the three recorders, translation
  language, microphone picker, and mute toggle
  (`.amp/in/artifacts/brand-menubar.png`, `about-pane.png`,
  `dictation-pane-features.png`).
- ⌘⇧V fired the handler in the running app (`hotkey` log line
  "paste-last shortcut fired" from a synthetic keystroke in TextEdit).
- `AudioOutputMute` mute/unmute verified from a standalone Swift harness
  compiled against the source (`output muted` false → true → false).

## Gaps

- The app under test had no Accessibility grant for the newly signed build,
  so the fn hotkey tap and hands-free sessions did not start during
  verification. Ask Anything, Translate, selection replacement, the answer
  panel, mute during a real recording, and the new-microphone notice were
  not exercised live. One Accessibility re-grant for the signed build is
  needed, then those paths can be run.
- `open "jot://..."` without `-a` launches `/Applications/Jot.app` or
  `/Volumes/Jot/Jot.app` (older copies registered with LaunchServices), which
  quit because the debug app was running. Remove or replace those copies.
- Prompt quality of the rewritten defaults not evaluated against the live
  API.

## Delivery state

All work is uncommitted in the working tree on `main` (PR #12 merged locally
by fast-forward, not pushed). Nothing pushed, no PR.
