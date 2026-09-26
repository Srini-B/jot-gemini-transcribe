# 2026-09-26: Voice IQ identity, sided shortcuts, screen context, pill answers

Second wave of the same day; follows
`2026-09-26-voiceiq-rename-modes-shortcuts-prompts.md`.

## Why

- The tray icon was invisible: the template PNG had both black and white, so
  macOS tinting produced a blotch. The About icon was navy on black with no
  contrast, and the sidebar still showed the app name instead of the logo.
- The user asked for the bundle ID `io.blue.voiceiq`, the About pane
  reduced to icon, name, and version, all Jot links replaced, and a local
  Developer ID + notarization path (not run yet).
- Shortcuts had to distinguish the left and right Command/Control/Option
  keys, and the sindresorhus recorder cannot see key side.
- Dictation should send screenshots of what the user was looking at so
  names, paths, and error text are spelled right.
- Translate had no target-language picker, and the initial list (taken
  from the Gemini 3.5 Transcribe input table) lacked Tamil, Kannada, Urdu
  and others.
- Ask Anything should answer in the pill, never edit text, and never carry
  context between requests.

## What changed

- Identity: bundle ID `io.blue.voiceiq`, scheme `voiceiq://`, log
  subsystem `io.blue.voiceiq`. `KeychainStore` reads the new service first
  and migrates the `com.ammaar.jot` entry; `FileLayout` moves
  `Application Support/Jot` to `Voice IQ` once. Sidebar shows the wordmark
  (`Bundle.main.image(forResource:)`; SwiftUI `Image(name)` only searches
  asset catalogs), and the sidebar material now reaches the window top.
  About pane is icon, "Voice IQ", version only.
- Icons: `scripts/make-icons.swift` builds the app icon as the favicon mark
  on the logo's navy rounded square, the menu bar icon as a single-colour
  template silhouette, and the sidebar wordmarks.
- `scripts/release.sh` signs with "Developer ID Application: Blue Lobster
  Technology PTE. LTD (G8K3545FJ2)" and notarizes with `notarytool` using
  `APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD`, `APPLE_TEAM_ID` from the
  shell environment. The script was not executed (it submits to Apple);
  only a Release signing check ran. `docs/RELEASING.md` updated.
- Shortcuts: `KeyboardShortcuts` package removed. `ShortcutSpec` +
  `ShortcutStore` + `GlobalShortcutEngine` (CGEventTap, raw device modifier
  bits, opposite side must be unset). Recorder has a Side picker.
- Screen context: `ScreenContextCollector`, capture at session start and on
  app switch (0.5 s debounce), keep first + latest up to 4 images, 1280 px,
  JPEG 0.6, +2 s deadline per image capped at 60 s. `screenContextEnabled`
  default on, toggle in Settings → Dictation. Only `.dictate` mode.
- Translate: `GeminiLanguages.swift` replaced with the 99-language Live API
  list (name + BCP-47 code); searchable popover picker; untranslatable input
  returns a sentinel that becomes "Couldn't translate to <Language>" in the
  pill with nothing inserted.
- Ask Anything: `AnswerPanel` deleted; `PillState.answer` + `AnswerView`
  (scrollable, Markdown, Copy, Esc/outside click). One-shot, never inserts,
  answer becomes `lastResult` for ⌘⇧V.

## Decisions

- Favicon on navy for the app icon: the plain navy mark on macOS's dark
  dock had no contrast.
- Language list is the Live API list, not the Transcribe input list, because
  the target list must cover what Gemini can write, and it is the larger,
  more current table. Codes are stored for search only; the setting keeps
  the display name.
- Translation failure message is generic on purpose; Gemini does not report
  which side (input or target) it could not handle.
- Screen context is on by default because the user asked for "just works";
  the privacy doc and README state it and the toggle.
- Bundle ID change resets UserDefaults and TCC: onboarding shows once more
  and microphone, Accessibility, Input Monitoring, and Screen Recording must
  be re-granted. Keychain and App Support data migrate; a one-time Keychain
  access prompt appears for existing users.

## Verification

- `./scripts/build.sh`: 0 errors. `swift test --package-path JotCore`:
  209 tests, 9 skipped, 0 failures.
- Launch on the new bundle ID: onboarding completed once, both event taps
  running, Keychain migration and `LegacyMigration: completed` in the log.
- Screenshots inspected: `.amp/in/artifacts/about.png`, `dictation.png`,
  `langpicker-tam.png` (search "tam" → Tamil only, left-aligned field),
  `langpicker-selected.png` (row shows Tamil; `defaults read` confirmed,
  then reset to English), `menubar-icon-big.png`, `app-icon-512.png`.

## Gaps

- Not exercised live (needs speech into the microphone): Ask Anything pill
  answer rendering, translate error pill, screen-context capture and the
  real Screen Recording prompt, mute during recording, sided matching on a
  physical keyboard.
- `scripts/release.sh` not run; notarization untested.

## Delivery state

Uncommitted in the working tree on `main` (PR #12 merged locally, not
pushed). Nothing committed, pushed, or released.
