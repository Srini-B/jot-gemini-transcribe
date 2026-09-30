# 2026-09-30: Auto-learn reads the field when Return is pressed

## Report

- An edit made just before pressing Return was never learned in apps where
  Return sends and clears the message (Slack, WhatsApp, mail). A changed field
  is diffed only after it has held still for 4 s, and by then the edited text
  was gone.

## Change

- `EventTapEngine.onReturnKeyDown` fires on the tap thread for Return and
  keypad Enter, before the frontmost app receives the key.
- `EditLearner.captureBeforeReturn(frontmostPID:)` reads the frontmost app's
  polled fields with a 0.2 s AX timeout. The main actor then diffs that value
  as settled. The existing 4 s settle path is unchanged.
- One capture diffs every tracked insertion in the field (up to 20 within 2 h),
  so edits across several dictations in one notes field are learned together.
- Captures follow the polling window: within 10 min of the last dictation into
  that field.

## Verification

- `scripts/test.sh`: 192 tests, 0 failures. Mac Debug build passes.
- A throwaway test used the capture's diff (`EditDiff.locateWindows`, then
  `corrections`). The input was three dictations in one notes field, with hand
  typing between them and edits in the first and third. It learned "stack" →
  "pstack" and "super base" → "Supabase" and left the unedited one alone.
- Not verified live. The build shell has no Accessibility permission, so the
  tap firing and the read before a chat app clears its field were not tested in
  a running app.
