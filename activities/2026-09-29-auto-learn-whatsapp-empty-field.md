# 2026-09-29: Auto-learn never tracked a new WhatsApp message

## Report

- MacBook, 08:38, a dictation into WhatsApp: "…check the recent email from
  Nathan regarding the API contract." Edited to "Nitin" before sending and
  left alone; "Nitin" was never learned.

## Root cause

- Not the ordinary-word filter from 2026-09-28: lowercase "nitin" is not in
  the macOS spelling dictionary, so the filter lets it through.
- WhatsApp's message box (an `AXTextArea`) answers an empty box with
  `kAXErrorNoValue` instead of an empty string, while `AXNumberOfCharacters`
  is 0. `AXInserter.focusedField` requires a readable value, so it returned nil
  and `LearningInserter` never tracked the insertion. Any dictation that starts
  a new WhatsApp message, the usual case, was invisible to auto-learn. Once
  text is in the box the value reads normally.

## Change

- `AXInserter.fieldText(of:)` reads a no-value field that reports zero
  characters as "". `focusedField` and `FieldSnapshot.currentValue` use it; the
  insertion path keeps `stringValue(of:)`, so insertion behavior is unchanged.

## Verification

- A throwaway harness drove the real `EditLearner` against WhatsApp's empty
  message box through the same readability check `LearningInserter` uses:
  insert the 08:38 sentence, change "Nathan" to "Nitin", wait, clear the box.
  Before the change: the empty box read as nil and nothing was learned. After:
  it read as "" and "Nitin (heard as Nathan)" was learned. The harness used its
  own defaults domain, not VoiceiQ's dictionary.
- `scripts/test.sh`: 192 tests, 0 failures; Mac Debug build passes.
- The installed VoiceiQ (0.5.3) still has the bug until the next build.
