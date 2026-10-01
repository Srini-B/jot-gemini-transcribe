# 2026-10-01: Agent mode implementation

## Request

Build the fourth mode end to end on the decisions recorded in
`activities/2026-10-01-agent-mode-research.md`, without assuming the
developer's environment. Reference: `docs/AGENT-MODE.md`.

## Decisions

- **Core/App split.** Session, tools, conversation, transports and the loop
  live in `VoiceIQCore/Sources/AgentEngine` so they compile without AppKit.
  Screen capture, AX and CGEvent live in `App/Sources/Agent/NativeExecutor`
  because they need Peekaboo and TCC.
- **Peekaboo pinned by revision.** `PeekabooAutomationKit` has no tagged
  release, so `project.yml` pins commit `31d67ea8…`. It builds under
  `SWIFT_VERSION 5.10` with no changes.
- **Four transports, one loop.** OpenAI Chat, OpenAI Responses, Anthropic
  Messages and Google generateContent each map the same tool list and the
  same history. Anthropic gets `cache_control` on the system prompt, the
  last tool definition and the last content block; OpenAI and Google rely on
  automatic prefix caching, which depends on a byte-stable prefix.
- **Image pruning in batches.** Screenshots stay in history until six have
  accumulated, then the oldest are replaced by placeholders down to three.
  Pruning every third screenshot instead of every one keeps the cached
  prefix valid for most calls. Older turns keep their text.
- **25-step cap per command** and a risky-word confirmation
  (`NativeExecutor.riskyWords`) before send/pay/delete-like actions.
- **Observe first.** Every command begins with a screenshot plus an AX summary
  of the frontmost window, falling back to the active display. "Explain what
  I am looking at" works because of this, not because of a special case.
- **Override storage.** The agent provider blob is a JSON `UserDefaults`
  key (`agentProviderOverride`); the key alone goes to the Keychain
  (`KeychainStore.Secret.agentProvider`). Unset → the dictation route.
- **Shortcut default** ctrl+opt+G (`ShortcutAction.agent`), shown only in
  the Dictation pane's Experimental section next to the Agent mode toggle.
- **Debug-only hook** `voiceiq://agent/<command>` so the loop can be driven
  without a microphone or hotkey.

## Fixes found during verification

- **Panel never appeared.** The HUD panel was only ordered in by
  `activateEngine()`, which never runs when Accessibility is denied, so the
  agent panel was built but invisible. `DictationController.openAgentPanel()`
  now repositions, starts the session, sets the `.agent` pill and shows the
  HUD itself. `stopAgent()` hides the HUD when the engine is inactive.
- **Answer shown twice.** Through the Anthropic format Claude wrote the
  answer as prose and then called the `answer` tool. `AgentLoop` no longer
  appends a reply's prose as a thought when the same reply carries an
  `answer` or `done` tool call.

## Verification

Debug build on the Mac mini, zero errors.

- Settings → Advanced → Experimental → Agent mode provider renders; Save &
  Validate against the user's CLIProxyAPI succeeded for OpenAI Chat and Google
  formats (green badge, "stored in Keychain", 43 models listed).
- The loop ran end to end via the debug URL on three transports: OpenAI Chat
  and Anthropic Messages with claude-sonnet-5-5, Google with
  gemini-3.8-flash-high (priced $0.00155). The panel showed the command
  bubble, the observation line and the answer.
- A second command, "What did I ask you first?", answered from history, so
  the session context works.
- Stop hides the panel when the engine is inactive.
- `usage.sqlite` holds the steps as activity `agent`, stage `agentStep`.
  Caching through CLIProxyAPI is measured for Claude: the first call was
  2411 in / 0 cached, the next command with the same system prompt and tools
  2 in / 2409 cached, and a second turn in the same session 818 in / 1862
  cached. The single Gemini call reported 0 cached, as expected for a first
  call.

Not verified on this machine: real screen capture, AX reads and CGEvent
actions, the hotkey and microphone path. The Debug build has no
Accessibility, Screen Recording or Microphone grants here and they cannot be
granted over SSH with SIP on. Cache behaviour for Gemini and for the OpenAI
Responses format across turns is unmeasured.

## Operational note

Debug builds are ad-hoc signed. After a rebuild the first Keychain read for
`agent-provider-api-key` blocks on a SecurityAgent prompt that never shows
over SSH. `.amp/in/relaunch.sh` deletes the item before launch; the key is
then re-entered through the UI. Release builds with a stable signing identity
do not hit this.

## Not done

No commit. All changes are uncommitted local edits. No History entry is
written for an agent transcript; Stop drops it.
