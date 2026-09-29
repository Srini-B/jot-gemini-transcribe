# 2026-09-29: macOS auto-update through GitHub Releases

## Decision

- Sparkle 2.10 (SPM) rather than a hand-written GitHub API check. Sparkle
  downloads, verifies the EdDSA signature and the Developer ID, replaces the
  app and relaunches; a hand-written checker could only point users at a
  download page.
- The feed is `appcast.xml` attached to every release and read through
  `releases/latest/download/appcast.xml`, so GitHub Releases is the only
  hosting and a release and its feed entry go live together. Rejected: a feed
  committed to the repository (needs a push per release, raw URLs are cached)
  and GitHub Pages (a second thing to deploy).
- Sparkle orders by `CFBundleVersion` (`CURRENT_PROJECT_VERSION`); the tag and
  file names use `MARKETING_VERSION`.
- Automatic checks and automatic download are on by default, without Sparkle's
  permission prompt. Both are in Settings › About. PRIVACY.md lists the check.
- Updates install when the app quits; the status menu offers "Restart to
  Install" meanwhile, since a menu bar app rarely quits and its alerts open
  behind other apps.
- The EdDSA key was generated on the MacBook into the login keychain (account
  `voiceiq`). Its public half is `SUPublicEDKey` in `project.yml`.

## Verification

- Debug build with ad-hoc and Apple Development signing: `codesign --verify
  --deep --strict` passes; Sparkle's XPC services are removed and its helpers
  carry the app's signature with hardened runtime.
- End to end on the MacBook with two builds under `io.blue.voiceiq.updatetest`
  (0.5.3/28 and 0.5.4/29) and a local feed made by `generate_appcast`:
  - automatic path: the 28 build checked at launch, downloaded 29, logged
    "update 0.5.4 downloaded; installs on quit", and was 29 after quitting;
  - "Restart to Install VoiceiQ 0.5.4" in the status menu installed and
    relaunched as build 29;
  - with automatic download off, the menu read "Install VoiceiQ 0.5.4…" and
    Sparkle's alert appeared; a click on its Install button (not made by the
    automation) installed and relaunched as build 29;
  - Sparkle logged "EdDSA signature is correct for update";
  - the Settings › About checkbox changed `SUAutomaticallyUpdate` in defaults.
- `scripts/verify-appcast.swift` accepted the generated appcast and rejected a
  build not in the feed and a ZIP with one byte changed.
- The test builds shared `~/Library/Application Support/VoiceiQ` with the real
  app. They applied the same 7-day audio retention the real app uses (one audio
  file purged) and started the retry queue drain; their logs show no
  transcription request.

## Rollout

Builds up to 0.5.3 have no updater, so the first Sparkle release is installed
from its DMG once. Procedure: docs/UPDATES.md. Rollback: publish a higher build
with the fix; never delete a release the appcast still lists.
