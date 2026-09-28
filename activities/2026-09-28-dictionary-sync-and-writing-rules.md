# 2026-09-28: Dictionary parity, iCloud sync, keyboard add, writing rules stay on

## Why

- The owner asked for the iOS gaps against the Mac to be closed: the
  Dictionary (search, CSV, Auto-learned with "Heard as"), the Dictation page
  going stale after a setting changed elsewhere, and the Advanced endpoint
  warning.
- Writing rules must never switch themselves off. The old auto-degrade turned
  them off after three rejected rewrites in 24 hours (on the Mac with a
  notice, on iOS silently).
- The dictionary should be the same on the Mac and iPhone through iCloud,
  always on. Auto-learning only exists on the Mac, and people rarely type words
  into the iPhone's Dictionary by hand.
- The keyboard should offer to add selected text to the dictionary.

## Decisions

- Auto-degrade removed from the shared core (`GeminiTranscriptionService`,
  `SettingsStore.recordGateTrip`, the Mac notice). A rejected rewrite still
  inserts the raw transcript for that dictation. One-time migration
  `restoreAutoDegradedWritingRulesOnce` (Mac and iPhone) turns writing rules
  back on when `gateTrips` shows the three-trip fingerprint and they are off.
- Sync uses iCloud key-value storage, not CloudKit: the dictionary is small,
  needs no container or schema, and the App Store Connect API (asc) can enable
  it. One value (`dictionary.v1`) in a store shared by both apps
  (`G8K3545FJ2.io.blue.voiceiq`). Merge is per entry with `updatedAt`,
  deletions as tombstones (180 days), and same-word duplicates collapse to the
  older entry. Checked with a throwaway XCTest (order independence,
  convergence, star and delete from two devices, re-add after delete), deleted
  afterwards per the owner's no-new-tests rule.
- A keyboard sees only its own field, so "selected anywhere" is covered two
  ways: a selection in the field, and, for text selected elsewhere, the last
  copy, offered once on the next keyboard appearance through the system
  `PasteButton`. A plain `UIPasteboard.string` read from the keyboard returned
  nothing for another app's copy in the Simulator; the paste button does.

## Account and signing (asc, API key)

- Registered App ID `io.blue.voiceiq` (the Mac app had none) and enabled
  iCloud (`ICLOUD`, Xcode 6 style) on it and on `io.blue.voiceiq.ios`.
- Created the Developer ID profile "VoiceiQ macOS Developer ID".
  Mac Release signs with `App/VoiceIQ-Release.entitlements` and this profile;
  Debug stays ad-hoc without iCloud.
- Deleted and recreated "VoiceiQ iOS App Store" so it carries
  iCloud; installed it and moved the old file out. Both profiles allow the
  key-value store `G8K3545FJ2.*`.

## Verification

- `scripts/test.sh`: 192 tests, 0 failures (one auto-degrade test removed).
  `scripts/build.sh` and the iOS simulator build pass.
- Mac Release on the MacBook (Developer ID, hardened runtime): signed with the
  profile embedded and the key-value entitlement, launched, wrote
  `dictionary.v1`; `syncdefaultsd` sent the change to iCloud
  (`CKSyncEngine-SendChanges`, container `com.apple.KeyValueService`).
- iOS App Store archive (`UPLOAD=none scripts/release-ios.sh`, build 26):
  signed, App Group and key-value entitlement present.
- Simulator: selecting "Kubernetes" in a Reminders title showed "Add
  “Kubernetes” to Dictionary"; tapping it added the word in the app. Copying
  "review" in Reminders, then reopening the keyboard, showed "Add copied text
  to Dictionary"; the paste button added it. Dictionary page shows both, with
  search pinned. Advanced shows the endpoint warning for `notaurl` (field
  cleared afterwards).
- Not verified: sync between two devices end to end (the Simulator has no
  iCloud account). The first check is the owner's iPhone on the next
  TestFlight build with the MacBook app running.
