# 2026-10-01: Agent mode research

## Request

A fourth mode, Agent, where the user commands the Mac by voice and one model
answers or acts, in a window the size of the Ask Anything answer panel that
keeps the session's transcript until the user stops it. Research only. Two
rounds: the first compared Hey Clicky, cua-driver and the alternatives; the
second fixed the action layer and added product constraints.

## Decisions

Written up in `docs/design/agent-mode-research.md`.

- **Native Swift AX + CGEvent with Peekaboo** is the action layer. The user
  chose it over bundling cua-driver, accepting the extra work. Peekaboo's root
  package (`PeekabooAutomationKit`, MIT, macOS 14) is consumable over SPM; its
  agent runtime is a nested package with path dependencies and is not. We
  write the loop ourselves.
- **No virtual cursor.** Hey Clicky removed theirs in 1.0.52 for drawing over
  the wrong app and blacking out captures.
- **Experimental placement.** Toggle and shortcut in the Dictation pane's
  Experimental section, not the Shortcuts list. Provider override in the
  Advanced pane's Experimental section next to the gateways.
- **Agent-only provider override** with base URL, key, four API formats,
  headers, query parameters, several model IDs with display names and one
  selected. Unset falls back to the dictation route. Primary target is
  CLIProxyAPI; the user's instance (8.0.7) lists Claude 5, GPT-6 and Gemini 3.x models,
  which is how Anthropic's models become reachable.
- **One model** for planning and execution; function tools on every format,
  native computer tools deferred.
- **Observe before deciding.** Every command starts with a screenshot and
  an AX summary of the active display, so "explain what I'm looking at" and
  "explain a quadratic equation" both see the screen first.
- **Status inline** in the expanded pill, no separate card, no always-on
  listening.

## Verification

Read-only. Live `GET /v1/models` on the user's CLIProxyAPI over SSH returned
32 models; Peekaboo facts come from the repository on the day; provider docs
read directly. Not verified: CLIProxyAPI passthrough of prompt-cache fields
and of the Anthropic computer tool, and whether a Swift 5.10 project consumes
Peekaboo's Swift 6.2 package cleanly.

## Not done

No code. The user's cua-driver element failures are not root-caused; the
document asks for ten recorded failures before building the executor.
