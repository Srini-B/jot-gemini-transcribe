# Agent rules

- Whenever the macOS application needs to be tested, test a signed and notarized build: produce it with the release flow (`scripts/release.sh`), install it, and test the installed app. Never test on a Debug build.
