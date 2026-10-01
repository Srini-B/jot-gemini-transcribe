# 2026-10-01 — Agent mode: first MacBook test feedback

Follow-up to `2026-10-01-agent-mode-implementation.md`. The user ran the
notarized 0.5.8 (33) build on the MacBook with GPT-6 Luna through CLIProxyAPI
and reported four things. Behaviour is documented in `docs/AGENT-MODE.md`.

## What was reported and why it happened

1. **Agent commands showed up in History.** The agent reused the dictation
   recording session, and `completeTranscription` kept every recording.
2. **The agent would not look things up.** Asked for a person's name in a
   YouTube video it said it could not tell from the image and asked the
   user for more, then tried a Chrome search and observed before the result
   page had loaded. It had no web tool and no settle time after actions.
3. **"Switch back to the amp" failed once.** The user had clicked Speak in
   the panel, which activated VoiceiQ; the agent then saw WhatsApp as
   frontmost and could not change that. The next command via the shortcut
   (no click) worked.
4. `previous_response_id` was rejected with 400 on every Responses call.

## Decisions

- Agent runs get their own store and section rather than a filter in
  History. `DictationMode.keepsRecording` is false for `.agent`, and
  `DictationCoordinator.discardUnlessKept()` drops the recording on
  completion, failure and cancel. Sessions are saved as JSON under
  `agent-runs/` by `AgentRunStore` on every transcript change with at least
  one command. The main window gains an **Agent** section between Meetings
  and Dictionary with list, detail, Copy, Delete and Delete All. History's
  Delete All leaves agent runs alone; each pane owns its data.
- `web_search` and `fetch_page` tools use the existing TinyFish key when
  one is saved; the system prompt tells the model to look things up before
  asking the user. `wait` lets the model give a page time to load.
- `NativeExecutor` sleeps after a successful action before the loop
  observes again: 800 ms for click, click_at, press, invoke_menu; 300 ms
  type; 400 ms scroll; 1 s open_app. Values are a first guess.
- Panel focus: `PillHUDController` already refuses key and main. The
  hand-back in `DictationController` covers systems where a click still
  activates VoiceiQ: it remembers the last foreign frontmost app and, on
  `didBecomeActive` with the panel open and no regular window visible,
  activates that app again. The root cause on the MacBook was not
  reproduced here.
- `AgentTransport.hostState` remembers a 400/404 on `previous_response_id`
  for the process and resends the full conversation afterwards. One extra
  failed call per process instead of one per turn.

## Verification (Debug build on the Mac mini)

- Build: zero errors.
- Two debug runs (`voiceiq://agent/<command>`) wrote
  `~/Library/Application Support/VoiceiQ/agent-runs/<uuid>.json`;
  `history.sqlite` `dictation` table stayed at 0 rows.
- `voiceiq://settings/agent` renders the Agent pane with both runs; Delete
  removed the file and the row. Screenshots:
  `.amp/in/artifacts/agent-pane.png`, `agent-pane2.png`.
- Focus hand-back: with Finder frontmost and the panel open, activating
  VoiceiQ programmatically logged "agent panel activated VoiceiQ; handing
  focus back to Finder" and Finder stayed frontmost. With the Advanced
  window open, no hand-back (as designed).

## Not verified here

The Mac mini Debug build has no Accessibility, Screen Recording or
microphone grants, so these need the MacBook:

- The spoken path: a real transcript reaching the agent and not History.
- The settle delays against Chrome search and app launches.
- `previous_response_id` behaviour with GPT-6 Luna (the 400 should appear
  once per launch, then stop).
- Whether a panel click still activates VoiceiQ on the MacBook, and the
  hand-back there.
- `web_search` end to end with a TinyFish key.

Caveat kept: the endpoint and key are read when the panel opens; a key
saved while the panel is open needs Stop and reopen.

All changes are uncommitted local edits. No commit, push or release was
authorized for this round.
