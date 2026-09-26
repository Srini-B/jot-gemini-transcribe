# 2026-09-26: TinyFish web context for Ask Anything, post-push fixes

Third wave of the day; follows
`2026-09-26-voiceiq-identity-shortcuts-screen-context.md`.

## Why

- On launch the pill said "New microphone detected" followed by a raw UID.
  CoreAudio creates private aggregate input devices for the capturing
  process (`CADefaultDeviceAggregate-<pid>-0`) whose name equals the UID
  and changes every launch, so each launch looked like a new microphone.
- The selected sidebar row drew white text on the light-blue dark-mode
  primary and was unreadable.
- The translation language popover had a different background for the
  list and field, showed ISO codes, and laid rows out right to left.
- Ask Anything had no access to current information. Gemini's own
  `google_search` grounding on `generateContent` is model-decided and
  not exposed through the cleanup call, so the user asked for TinyFish
  Search + Fetch (free) with a user-entered key, "just like Gemini".

## What changed

- `AudioInputDevices.list()` skips aggregate devices whose composition
  marks them private. Stale UIDs already in `seenInputDeviceUIDs` are
  harmless because those devices are no longer listed.
- Sidebar selected text uses `JotUI.Colors.onPrimary`.
- `LanguagePicker` is a `ScrollView` + `LazyVStack`, left aligned, name
  only, one background.
- `KeychainStore` gained `Secret` (`gemini`, `tinyFish`) and
  `load/save/deleteTinyFishKey`; change notifications use
  `Secret.settingKey` (`apiKey`, `tinyFishKey`).
- New `TinyFishClient` (search, fetch, key check) and `WebContext.gather`.
  For Ask Anything with a stored key: Gemini decides via
  `PromptV1.webSearchQueryPrompt` whether a search is needed and returns
  the query or `NONE`; TinyFish search → top 3 fetch → 6 000 chars each →
  `<web_context>` in `askAnythingPrompt`, which asks the model to prefer
  it for facts and add a Sources line. Failures fall back silently.
- Settings → Advanced: `TinyFishKeySection` below the Gemini key.
  Privacy pane lists screen snapshots and the TinyFish search.
- Docs: `docs/PRIVACY.md` item 5, README, architecture.

## Decisions

- Search is gated by a Gemini decision call rather than always-on, so
  rewrites and edits do not pay 2 to 5 s of search latency. Cost is one
  short flash call (~1 s) per Ask Anything when a key exists.
- Translate stays on transcribe → text translation on `cleanupModel`.
  `gemini-3.5-live-translate-preview` exists but takes no instructions
  (no dictionary terms, no untranslatable sentinel) and returns audio
  plus a transcript; switching is a separate decision.

## Verification

- `./scripts/build.sh`: 0 errors. `swift test --package-path JotCore`:
  see the thread for the count.
- Launched the Debug app: pill idle with no microphone notice; Dictation
  window screenshot shows dark text on the selected sidebar row; language
  popover filtered "span" to "Spanish" with one background and no code.
- TinyFish live check with the key from `~/.zshrc`: search returned 9
  results for "voice iq"; fetch of the first URL returned 2 786 chars of
  Markdown. `final_url` drops the trailing slash, so pages are matched on
  the echoed `url`.
