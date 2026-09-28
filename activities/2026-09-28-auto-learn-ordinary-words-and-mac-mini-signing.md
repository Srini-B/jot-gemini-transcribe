# 2026-09-28: Auto-learn skips ordinary words; Mac mini signing setup

## Auto-learn

### Why

- The MacBook's Dictionary had six auto-learned entries: `pstack` (from
  "Paystack"), `VoiceiQ` (from "VoiceIQ"), `there's` (from "There's"), `we`
  (from "they"), `Learned` (from "Learn") and `last` (from "a"). The last four
  are ordinary English: a case fix and word-choice edits. The owner wants only
  words that are not in a dictionary to be learned.

### Findings

- `NSSpellChecker` in lowercase separates them: it knows "there's", "we",
  "learned", "last", "they", "gonna", "walked", but not "pstack", "voiceiq",
  "supabase", "revenuecat", "kubernetes", "priya", "hafeez", "grpc",
  "testflight". Capitalized, it accepts almost any word as a possible proper
  noun ("Kubernetes", "RevenueCat", "Priya" all "known"), so the check must be
  lowercase. Tried with `en` and `en_US` on the Mac mini (user languages start
  with `en_IN`); same answers.

### Change

- `CommonWords.isOrdinary` (VoiceIQCore/Learning, macOS): true when every word
  is in the spelling dictionary, checked in lowercase against the user's
  English variant and `en`. `EditLearner.learn` skips such corrections.
- One-time `EditLearner.pruneOrdinaryAutoLearnedOnce` at launch, before
  dictionary sync starts, removes auto-learned ordinary words (entries the user
  added are untouched). On the MacBook this removes `there's`, `we`, `Learned`
  and `last` on the next launch of a build with this change; the deletions sync
  to the iPhone.
- A throwaway XCTest (deleted) checked the six MacBook words, ten names and
  product terms, six ordinary words, and the prune.

## Mac mini as a Mac release machine

- Had: notarization credentials in `~/.zshrc` (`notarytool history`
  succeeded), asc, the release keychain with the Apple Distribution identity.
- Added: the "VoiceiQ macOS Developer ID" profile (installed), and
  `scripts/setup-mac-signing.sh`, which creates or unlocks the release
  keychain, imports a Developer ID `.p12`, installs the profile with asc, and
  checks the notarization variables. `release.sh` now unlocks the release
  keychain and fails early without the identity, like `release-ios.sh`.
- Missing: the Developer ID Application identity itself. Creating a new
  certificate with the API key failed ("This operation can only be performed by
  the Account Holder"). Exporting the MacBook's identity over SSH failed
  ("User interaction is not allowed"): macOS asks for the login password at the
  MacBook. The owner exports it once as a `.p12`; then the setup script imports
  it. Steps in docs/RELEASING.md.
