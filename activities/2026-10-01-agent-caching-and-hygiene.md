# 2026-10-01 — Agent caching measured, screenshot cleanup, pill flash, re-edited learned words

Follow-up to `2026-10-01-agent-mode-macbook-feedback.md`. The user asked
seven questions after the second MacBook round; four needed code. Behaviour
is documented in `docs/AGENT-MODE.md` and `docs/design/architecture.md`
(auto-learn).

## Answers that needed no code

- Agent commands are transcribed by the dictation provider and model, not
  the agent endpoint. They are faster because `.agent` skips the live
  stream, the writing-rules pass and the second opinion, like Ask Anything.
- There is no confidence score. A command runs until the model replies with
  no tool calls or calls `answer`/`done`, capped at 25 steps.

## Caching: measured, one finding, one change

A throwaway harness (`.amp/in/cacheprobe`, builds against the local
`VoiceIQCore`) drove `AgentTransport` with the real prompt and tools, three
commands and fake per-step screenshots, and printed each host's usage.

- OpenAI Chat caches 56 % of input with `prompt_cache_key` and 5 s gaps;
  misses are only on prefixes younger than about 10 s.
- OpenAI Responses with `previous_response_id` cached 2 of 16 continuation
  calls across five runs (0–18 % of input). Resending the whole conversation
  cached 28–47 %. The stored-context handle was removed from the transport,
  along with the proxy fallback that existed only for it.
- `prompt_cache_key` (one id per session) is now sent to `*.openai.com`
  hosts only; other hosts are not known to accept the field.
- CLIProxyAPI → gpt-6-luna (Responses) cached 50 %.
- CLIProxyAPI → gemini-3.8-flash-high returned no `cachedContentTokenCount`
  at all, even for an identical 4 000-token prefix sent twice 12 s apart.
  Direct Gemini was not measured: no key on the build machine.

Still open: whether a host that reports no cache field bills the uncached
rate, OpenRouter and Vercel behaviour, and a per-session cost cap (none
exists; 25 steps per command is the only bound).

## Screenshots on disk

Peekaboo writes one full-resolution PNG per observation to `$TMPDIR` and
never deletes it; the MacBook had 18 of them (0.2–2.9 MB each) after build
33. The PNG is required: Peekaboo only registers the element snapshot for
element-id clicks inside the write path. `NativeExecutor` now points the
write at `$TMPDIR/VoiceiQ-agent/`, deletes the file right after `observe`
returns (click and scroll only check the path string, not the file), and
purges the directory on init. The 18 legacy files on the MacBook were left
for macOS's three-day temp purge; deleting them needs the user's say.

## Pill flash at launch

`PillModel.state` starts as `.idleDot`, `activateEngine()` showed the panel
at once, and the `.idle → hidden` mapping (showIdleIndicator off) arrived on
a later main-queue hop through `bind()`. `activateEngine()` now paints
`restingPill(for: coordinator.state)` through `setPill` before `hud.show()`,
so the mapping stays in one place.

## Learned word edited again

`EditLearner.learn` skipped a correction whose original was already a
dictionary term, so fixing a just-learned word ("Pastack" → "pstack") was
ignored. An `.auto` entry edited within `reEditSeconds` (120 s; the settle
window is 4 s so "a couple of seconds" is covered with margin) is now renamed
in place through `DictionaryStore.update(id:term:)`, or removed when the new
wording is ordinary or already a term. Same id, so sync sees an edit.

## Verification

- Debug build: compiles. Per the new root `AGENTS.md`, testing is on the
  signed, notarized build only (`scripts/release.sh`, SKIP_TESTS=1).
- Caching numbers above are from live calls against api.openai.com and
  CLIProxyAPI on 2026-10-01.

## Notarized-build checks (Mac mini, 2026-10-01)

- `scripts/release.sh` (SKIP_TESTS=1): notarization "Accepted", ticket
  stapled. 0.5.8 build 33, same numbers as the build already installed.
  Installed to `/Applications` after quitting the old copy; `spctl -a`
  reports "Notarized Developer ID", `stapler validate` passes.
- Pill flash: not reproduced on the old build either. A cua-driver screen
  recording across quit → relaunch of the previous build 33 kept the bottom
  260 px of the 1920×1080 display unchanged (per-pixel scan,
  `.amp/in/frames2.swift`); the recorder emits frames only when the screen
  changes and the strip never did. So the fix stands on code reading, not on
  a before/after capture. The flash would be at most one main-queue hop
  long, under the recorder's 33 ms frame interval.
- Screenshot hygiene: cannot be exercised here. Screen Recording is not
  granted to VoiceiQ on the Mac mini, so `observe` returns the permission
  notice before Peekaboo captures anything, and `voiceiq://agent/<command>`
  is a Debug-only hook. The MacBook, where the 18 files were found, has the
  grant; a run there is the real check.
- Re-edit learning: `learn` is private and driven by an AX field poll, so
  it was not driven headlessly. `DictionaryStore.save` re-stamps `updatedAt`
  on the renamed entry, so the 120 s window restarts at each rename.

All changes are uncommitted local edits. No commit, push or release was
authorized.

## Second pass: caching by model family, em dash ban, provider UI, User-Agent

The user asked for caching that follows the chosen model's vendor on every
host, as close to each vendor's guidance as possible.

### Why the policy moved from host to model

One CLIProxyAPI URL serves GPT, Claude and Gemini ids, so the old rule
(`prompt_cache_key` only for `*.openai.com`, breakpoints only in the
Anthropic format) left a Claude model on a Chat-format proxy with no
breakpoints and a GPT model on the proxy with no key. `ModelFamily.infer`
now classifies the id (`claude*`, `gemini*`/`gemma*`, `gpt*`/`o*`), and
`AgentCachePolicy` decides the fields. Unknown hosts that reject a field
answer 400; the transport retries that one call without the fields and
keeps the session plain afterwards, so a strict host costs one round trip.

Static prefix (tools, system) for Claude is written with `ttl: "1h"` at 2×
the write price instead of 1.25×, because a user who pauses more than five
minutes between commands would otherwise rewrite the whole prefix; the
moving breakpoint stays at five minutes. Reversible by changing
`AgentCachePolicy.staticTTL`.

### Measured after the change (`.amp/in/cacheprobe`, live calls)

- api.openai.com Chat, gpt-4.1-mini: 70 % (was 56 %).
- CLIProxyAPI Responses, gpt-6-luna: 70 % (was 50 %).
- CLIProxyAPI Anthropic Messages, claude-haiku-4-5: 63 %; every call after
  the first cached everything before the newest message.
- CLIProxyAPI Chat format with a Claude id: same per-call hits; the proxy
  accepts `cache_control` in Chat bodies, so the 400 fallback was not
  exercised live. It is covered only by code reading.
- CLIProxyAPI Gemini, gemini-3.5-flash-lite: 48 %. Raw probes show the
  implicit cache works in 4,096-token blocks and never caches the trailing
  partial block, so a 4,562-token prompt caches nothing and a 14,806-token
  prompt caches 12,258.
- CLIProxyAPI Gemini, gemini-3.8-flash-high: 0 %. The proxy's antigravity
  route hits only on a byte-identical prompt; a 7,000-token system prompt
  with a different one-line user turn missed every time, while the flash-lite
  ids on the same proxy hit on prefix. A host limitation, not a client one.

Earlier finding corrected: the old "no `cachedContentTokenCount` at all"
note was the trailing-block rule, not a missing field.

### Other changes

- Writing rules (`PromptV1.rules`), the agent system prompt and the meeting
  notes prompt now forbid em and en dashes; a spoken "dash" stays a hyphen.
- The agent provider section adds a model from two full-width rows, "New
  model ID" and "Display name", with an Add Model button under them; the
  shared row clipped the placeholders.
- Agent requests send `User-Agent: VoiceiQ/<version> (<build>)`. Before, no
  request in the app set an identifying header; URLSession's default
  `VoiceiQ/<build> CFNetwork/… Darwin/…` was all a host saw. Dictation
  clients still rely on that default.
- The 14 Peekaboo PNGs still in the MacBook's `$TMPDIR` were deleted on the
  user's say (macOS had already purged 4 of the 18).

### Verification

- Debug compile passes.
- `scripts/release.sh` (SKIP_TESTS=1): notarization Accepted, stapled,
  `spctl` reports Notarized Developer ID. Still 0.5.8 build 33. The running
  copy was quit and the new one installed to `/Applications` on the Mac mini.
- Advanced → Experimental → Agent mode provider inspected on the installed
  build through cua-driver: "New model ID" and "Display name" are separate
  full-width rows with their placeholders fully visible, Add Model below
  them (`.amp/in/artifacts/advanced-3.png`).
- Not exercised live: the 400 fallback (no host at hand rejects the fields)
  and the em dash rule's effect on model output.
