# 2026-09-30: iOS when the microphone or keyboard is taken away

## Why

The owner asked whether the iPhone app reacts correctly when a user turns off
the microphone, the keyboard, or Full Access after onboarding.

## Found

- Microphone off. iOS ends the app when a privacy permission is turned off,
  and on the next launch Finish setup shows the Microphone line unchecked
  (seen in the Simulator). A dictation cannot start: `startBlocker` refuses
  it. But a keyboard tap that opened the app (`startFromKeyboard`) began the
  voice session before that check. That session could not record. The app
  then sent the user back to the host app with the one-line keyboard notice
  "Allow the microphone in VoiceiQ". Start meeting had no check at all. The
  Action button posted its notice where nothing showed it.
- Keyboard removed. `keyboardAdded` followed Settings, but the Full Access
  proof (`keyboardSeenAt`) was never cleared. A keyboard added back without
  Full Access showed as Ready.
- Full Access off. The keyboard itself handles it: it shows "Allow Full
  Access", which opens the setup sheet. The app kept showing Ready, because
  the keyboard cannot write to the App Group without Full Access.

## What changed

- `AppModel.startFromKeyboard` checks the API key and microphone before it
  opens a session. When either is missing it stays in VoiceiQ with a banner.
  For the microphone it also shows Keyboard & Permissions, and asks for the
  permission if iOS has not asked yet. `startMeeting` does the same for the
  microphone.
- `ActionButtonBridge.toggle` returns the refusal, and `ToggleDictationIntent`
  throws it as `ActionButtonRefusal` so the system shows it.
- `SetupStatus.current()` clears `keyboardSeenAt` when the keyboard is not
  in the keyboards list. `AppModel.open(.setup)` clears it too, because only a
  keyboard without Full Access opens that link.

## Verification

- `scripts/build-ios.sh` and `scripts/test.sh` (192 tests, 9 skipped, 0
  failures) pass. `scripts/build.sh` passes once the stale Debug app is
  removed. It failed first in the "Sign Sparkle helpers" phase, the same
  stale-product failure seen earlier today.
- Simulator (iPhone 18 Pro Max, iOS 27):
  - Microphone revoked with `simctl privacy`, then launched: Finish setup
    showed Microphone unchecked.
  - Keyboard removed from `AppleKeyboards`, then relaunched: "Keyboard and
    Full Access" unchecked, Try it said "Waiting for the VoiceiQ keyboard",
    and `bridge.keyboardSeenAt` was gone from the App Group.
  - Keyboard added back: the line showed the waiting clock, not Ready.
- Not verified on screen: the keyboard-start refusal, the setup link, Start
  meeting and the Action button message. The Simulator accepted no taps from
  `axe` (the "Open in VoiceiQ?" prompt from `simctl openurl` and the app's own
  text field ignored them), and there is no Simulator.app on this Mac to
  click into. On a phone: turn the microphone off for VoiceiQ, tap the mic
  on the keyboard in Notes, and expect VoiceiQ to stay open with the banner
  and the permissions sheet.
