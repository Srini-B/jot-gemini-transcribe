# 2026-09-29: Release automation, update pill, license headers

## Requests

- Remove the Apache/Google license header from every file.
- Updates install automatically by default, never during a session, and the
  pill says when one is ready, with a Restart button. Check every 6 hours.
- Build the iPhone app in GitHub Actions and ship it to TestFlight with asc;
  release both apps with one version when `MARKETING_VERSION` changes; tag
  automatically; write release notes with gpt-6-luna from the changes since
  the previous version and use them in Sparkle too.
- Fix or remove the `grep -q` + `pipefail` check in `release.sh`.

## Decisions

- License headers removed from 184 files (Swift, C, Objective-C, shell,
  Python, YAML, the xcframework header). `LICENSE`, `THIRD_PARTY_NOTICES.md`,
  vendored notices and the `NSHumanReadableCopyright` string are unchanged.
- Update install: the app takes over from Sparkle (`willInstallUpdateOnQuit`
  returns true). Restart on the pill installs at once; otherwise it installs
  when nothing is in use and there has been no input for 5 minutes, or on quit.
  A relaunch shows "Updated to VoiceiQ x.y.z".
- Versions: one `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` under
  project-level `settings`, instead of four copies. `release-ios.sh` no longer
  picks a higher build number from TestFlight; it fails instead, so both apps
  always carry the same build.
- CI runs on GitHub-hosted `macos-26` (Xcode 26.6), not a self-hosted runner on
  the Mac mini: the repository is public, and a self-hosted runner would run
  code from anyone who can open a pull request.
- One `.p12` with both identities, exported from the Mac mini's release
  keychain; profiles are downloaded by name at build time. Notarization uses
  the App Store Connect key, so the Apple ID password is not a secret.
- Secrets were set with `gh secret set`, piping each value from its source,
  rather than typed into the GitHub website, so no secret passed through the
  agent's transcript or screenshots.
- The publish job waits for both builds, so a failed iPhone build stops the Mac
  release.

## Verification

- `scripts/test.sh`: 192 tests, 0 failures. Mac Debug build passes.
- Mac mini, with CI's environment-variable auth: iOS archive and export
  (app, keyboard and Live Activity all 0.5.3 (28)); Mac build notarized with
  the API key (app and DMG accepted); asc reports next build 29.
- `scripts/ci-plan-release.sh`: releases on a version bump and on a manual
  run, not on a push without one or with no previous commit.
- `scripts/generate-release-notes.py` found 0.5.2 at `3a28317` and produced
  notes for 0.5.3 with gpt-6-luna.
- Update pill, with two local builds under `io.blue.voiceiq.updatetest`: the
  pill read "VoiceiQ 0.5.4 is ready" with Restart; Restart relaunched as 0.5.4;
  the relaunch showed "Updated to VoiceiQ 0.5.4". A copy with a 20-second idle
  threshold installed on its own 60 s after the download.
- The Sparkle key copied to the Mac mini signs a file that verifies under
  `SUPublicEDKey`.
- No secret value (ASC key ID, issuer, `.p8`, OpenAI key, p12 and keychain
  passwords, Apple ID credentials, Sparkle key) appears in any tracked or new file.
- Not run: the workflow itself on GitHub, which needs these changes pushed.
