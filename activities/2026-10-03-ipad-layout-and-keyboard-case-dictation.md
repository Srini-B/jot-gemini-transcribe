# iPad layout and dictation with a keyboard case

2026-10-03. Released in 0.5.13 (38).

## Why

The app installed on iPad but ran as an iPhone app (`TARGETED_DEVICE_FAMILY`
`1`), so iPadOS showed the phone UI in a narrow, scaled window.

The owner uses an iPad with a keyboard case that is always attached. iPadOS
then shows no on-screen keyboard, so the VoiceiQ keyboard never appears, and
the case's dictation key starts Apple's dictation. There was no way to start a
VoiceiQ dictation.

## What changed

- `project.yml`: all three targets build for iPhone and iPad. The iPad
  supports every orientation (needed for Split View and Stage Manager); the
  iPhone stays portrait.
- `ListDetailNavigation` (`Components.swift`): a split view in regular width,
  a stack in compact width. History, Meetings and Settings use it. Selected
  History and Meetings rows switch to white text on the accent fill
  (`backgroundProminence`).
- The iPad sidebar hides its title (`toolbar(removing: .title)`), because the
  tabs at the top already name the page. The Settings placeholder reads
  "No setting selected" for the same reason.
- iPhone: the bottom tab bar minimizes while a page scrolls down.
- Home uses two columns in regular width. Scroll pages cap their width with
  `readableWidth()`. Copy that said "iPhone" names the actual device.
- Keyboard case: `ToggleDictationIntent` is now an App Shortcut
  ("Dictate with VoiceiQ"), so Spotlight, Siri and the Shortcuts app offer it
  with no setup, next to the existing Control Center control. The result goes
  to the clipboard as before. On iPad, Home, onboarding's Try it page and
  Settings › Dictation show a "Hardware keyboard" card with the steps, in place
  of the Action button section.

Apps cannot take over the case's dictation key, and third-party keyboards have
no hardware-keyboard mode, so the fix is an entry point outside the keyboard.

## Verification

- `xcodebuild` Debug for the iPad Pro 13-inch (M5) simulator, iPadOS 27.0:
  build succeeded.
- Driven in Device Hub: Home in portrait and landscape, History and Meetings
  in split view with a selected row, Settings › Dictation and Translate To in
  the detail column, onboarding welcome and Try it pages.
- `Metadata.appintents/extract.actionsdata` lists the App Shortcut, and the
  simulator's Shortcuts app shows VoiceiQ with one action.
- iPhone 18 Pro Max simulator: Home is unchanged (one column, bottom tab bar,
  Action button copy).
- Sidebar titles: History, Meetings and Settings on the iPad simulator show
  no title above the list; the detail column keeps its own.
- Tab bar: a drag on the iPhone 18 Pro Max Home page (Device Hub, through
  cua-driver) collapsed the tab bar to the Home icon.
- Not verified: running the intent from Spotlight, Control Center or Shortcuts
  and pasting the result. Device Hub did not deliver synthetic taps or keys to
  the simulator, so nothing could start it. Not tried on a physical iPad.
