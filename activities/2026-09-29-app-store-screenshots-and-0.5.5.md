# 2026-09-29: App Store screenshots and 0.5.5 (30)

## Requests

- App Review may need to get past onboarding without an API key. Add a skip on
  the key step if there is none.
- Take 4 to 8 App Store screenshots of the iPhone app in Device Hub.
- Raise the version and build, and release both apps to TestFlight.

## Decisions

- No code change for the skip. The key step already shows "Add a key later"
  while no key is saved, and the permissions step shows "Set up later".
  Verified in the Simulator: onboarding finishes without a key, and Home ›
  Finish setup › API key and Settings › Provider & Keys open the key form.
- Screenshots were taken on the iPhone 18 Pro Max Simulator (1320 × 2868, the
  6.9" App Store size) with the status bar set to 9:41, full signal and full
  battery. History and Home stats show eight sample dictations written straight
  into the Simulator's `history.sqlite`, because transcription needs a key.
- The Simulator was switched to US English with only the English (US), Emoji
  and VoiceiQ keyboards, so no Hindi keyboard or text appears in any frame.
- Version 0.5.4 (29) → 0.5.5 (30). The push to `main` runs the Release workflow,
  which uploads the iPhone build to TestFlight and publishes the Mac build.

## Verification

- `scripts/build.sh` and `scripts/build-ios.sh` pass.
- `EVENT=push BEFORE=HEAD scripts/ci-plan-release.sh` reports
  `release=true version=0.5.5 build=30`.
