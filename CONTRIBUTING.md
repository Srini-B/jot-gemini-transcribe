# Contributing to VoiceiQ

Bug reports, fixes, and features are welcome through GitHub issues and pull
requests. Open an issue first for anything larger than a focused fix, so the
approach can be agreed before the code is written.

## Getting started

```bash
brew install xcodegen
./scripts/build.sh                        # xcodegen generate + Debug build
swift test --package-path VoiceIQCore     # fast, headless
```

`docs/design/architecture.md` explains how the pieces fit. `docs/RELEASING.md`
covers signing and notarization; contributors do not need any of that for a
Debug build.

## Pull requests

Every submission is reviewed through a GitHub pull request. Keep a PR to one
change. Describe what changed, why, and how you verified it. Update `docs/`
when behavior, setup, or architecture changes.

By opening a pull request you confirm that you wrote the code, or otherwise have
the right to contribute it under this repository's license.

## Ground rules

1. **Swift, macOS, Gemini only.** No local models, no other AI providers, no
   cross-platform layers.
2. **It has to just work by default.** New behavior ships with a sensible default
   and no required setup. Add a setting only when users genuinely need to choose.
3. **Cleanroom policy.** GPL-licensed projects in this space may be studied for
   behavior, never copied. Do not port, translate, or paraphrase their code into
   this repository.
4. **No secrets, ever.** No API keys, tokens, or signing material in code,
   fixtures, tests, or CI files. The app takes the user's own keys at runtime and
   stores them in the Keychain.
5. **Design tokens only.** UI changes use `DesignTokens.swift` and
   `MotionTokens.swift`. If a value is not in the tokens file, add it there
   first. The full design contract is `docs/design/experience.md`.
6. **Prompt changes need evidence in the PR.** `PromptV1.swift` and
   `PromptV1+Modes.swift` steer the writing-rules pass. There is no automated
   eval set yet, so verify by hand and put the results in the PR: dictate a
   self-correction, a spoken list, question-shaped speech, spoken punctuation,
   and an all-filler take, and confirm the ValidationGate did not trip.
7. **Never-lose-words is an invariant.** Any change touching audio, networking,
   or insertion must keep these true: audio is on disk before network I/O
   begins; every failure writes a terminal status; errors are never modal;
   nothing is silently discarded.
8. **No telemetry.** PRs adding analytics, tracking, or phone-home behavior will
   be declined. The only network host is the Gemini API, plus TinyFish when the
   user has entered a key for it.
9. **Keep files small.** Around 500 lines per source file; split when it improves
   clarity, not to hit a number.
