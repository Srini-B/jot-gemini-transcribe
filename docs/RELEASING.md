# Releasing VoiceiQ

Releases are built locally with `scripts/release.sh`. The script produces a Developer ID signed, notarized, and stapled app and DMG. It stops on any signing, entitlement, notarization, or Gatekeeper failure.

## Prerequisites

The login keychain must contain this identity:

```text
Developer ID Application: Blue Lobster Technology PTE. LTD (G8K3545FJ2)
```

The shell must export these values before the script starts:

```bash
export APPLE_ID=...
export APPLE_APP_SPECIFIC_PASSWORD=...
export APPLE_TEAM_ID=...
```

The values are stored in `~/.zshrc` on the release machine. Source that file in the calling shell. The script checks that all three variables exist and never prints them.

## Build a release

1. Confirm `./scripts/test.sh` and `./scripts/build.sh` pass.
2. Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`.
3. Confirm the production Gemini models are available with a real dictation.
4. Run the release script.

```bash
source ~/.zshrc
./scripts/release.sh
```

The script performs this sequence:

1. Regenerates `VoiceIQ.xcodeproj` with XcodeGen.
2. Builds Release with manual Developer ID signing, hardened runtime, and a secure timestamp.
3. Verifies the app signature and rejects `get-task-allow`.
4. Creates a ZIP with `ditto` and submits it to Apple notarization.
5. Staples the app and checks it with Gatekeeper.
6. Builds `build/release/VoiceiQ-<version>.dmg` with `scripts/make-dmg.sh`.
7. Signs, notarizes, staples, and Gatekeeper-checks the DMG.

The bundle identifier is `io.blue.voiceiq`. Changing it resets the app's UserDefaults domain and requires users to grant microphone, Accessibility, and other TCC permissions again. `FileLayout` and `KeychainStore` migrate the previous VoiceiQ folder and API-key service, but macOS permissions cannot be migrated.

## Verification

Inspect an existing release without submitting another notarization job:

```bash
codesign -dvv "build/release/DerivedData/Build/Products/Release/VoiceiQ.app"
codesign -d --entitlements :- "build/release/DerivedData/Build/Products/Release/VoiceiQ.app"
spctl -a -t exec -vv "build/release/DerivedData/Build/Products/Release/VoiceiQ.app"
xcrun stapler validate "build/release/VoiceiQ-<version>.dmg"
spctl -a -t open --context context:primary-signature -vv "build/release/VoiceiQ-<version>.dmg"
```

Do not distribute an artifact if any command fails. There is no unsigned or unnotarized fallback.

## Every release

1. Complete the product reliability checklist in `docs/design/product-reliability.md`.
2. Smoke-test onboarding, API-key storage, permissions, dictation, history, and the DMG install flow on a clean macOS account.
3. Publish the verified DMG and release notes.
