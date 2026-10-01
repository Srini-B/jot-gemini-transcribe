# Agent mode research

> Research record, 2026-10-01, revised the same day after the user's second
> round of constraints. No code was written. Every claim names its source;
> anything not confirmed is marked *unverified*. Prices are list prices on
> the day of research.

Agent mode is the fourth mode after Dictation, Translation and Ask Anything.
The user speaks a command, one model decides whether to answer or act,
VoiceiQ performs the actions on the Mac, and the expanded pill keeps the
session's transcript (commands, thinking, actions, answers) until the user
stops it. The agent does not speak back and does not draw a cursor. The
feature ships under Experimental.

## Decisions fixed by the user

| Topic | Decision |
| --- | --- |
| Action layer | Native Swift (AXUIElement, CGEvent, ScreenCaptureKit), with Peekaboo as the reference and candidate dependency. cua-driver is not bundled or required. |
| Virtual cursor | None. |
| Placement | Toggle and shortcut live in the Experimental section, not in the Shortcuts list. |
| Model | One model plans and executes. No planner/executor split. |
| Provider | An agent-only custom provider override (base URL, key, API format, headers, query parameters, several model IDs with display names, one selected). Unset means the dictation route is used. Primary target is CLIProxyAPI; any compatible host works. |
| Status display | Inline in the expanded pill, interleaved with the user's commands. No separate card. |
| Always-on listening | Not built. |
| Intent handling | Vague ("explain what I'm looking at") and general ("explain a quadratic equation") commands both start by observing the active display. |

## 1. Hey Clicky, what we keep and what we skip

Source: heyclicky.com, its changelog, trust and privacy pages, and
github.com/farzaa/clicky (MIT origin). Maker Humansongs, Inc. (YC S26).
Version 1.0.52 on 2026-09-24, DMG from GitHub, macOS 14.2+. Free 25 Talk and
25 Agent messages a month; Pro $20 (150 Agent); Max $100 (1,000).

Kept: push-to-talk, live progress steps inside the conversation, a
persistent chat whose last ~40 messages are context, **Allow once / Always
allow / Not now** before the first click or keystroke (since 1.0.52 "yes"
covers one conversation), always-confirm for deletes, emails and money, Stop
and retry.

Skipped: spoken replies, hosted inference, named persistent "Clickys", the
top-right status card, Always On mode, and the floating cursor. Hey Clicky
itself removed the cursor in 1.0.52 because it drew over the wrong app and
blacked out window captures. Our no-cursor decision matches where they ended
up.

Control-layer history, from the changelog: May 2026 shipped on the Cua
driver ("early, sometimes it breaks"); v1.0.48 moved to their own native
driver with window-scoped background clicks that never move the real pointer;
v1.0.52 dropped the cursor. Models: GPT-6 Luna for agents, GPT-6 Sol for deep
answers. Reported failures: wrong-monitor placement, blank screenshots (apps
that block capture), slowness, repeated steps.

## 2. Action layer

### 2a. Native Swift, the chosen layer

What it reaches: AppKit and SwiftUI controls, menus, windows, text fields,
Finder, the Dock's AX tree (`com.apple.dock`), Spaces through private APIs.
`AXObserver` reports focus and value changes, which is how an action is
verified. Posting `CGEvent`s needs only Accessibility, not Input Monitoring.

Where it fails: Electron and Chromium expose their tree only when assistive
tech is detected (`AXManualAccessibility` or
`--force-renderer-accessibility`); Catalyst, Metal, canvas and WebGL views are
opaque; auto-hidden Dock items are absent until the Dock is revealed
(Hammerspoon discussion #3741); windows on other Spaces or in Stage Manager
look present but are not actionable; full-tree dumps are one IPC per
attribute and can return `kAXErrorCannotComplete`, so traversal must be
bounded. Coordinate spaces differ: AX and Quartz use top-left global points,
AppKit bottom-left, ScreenCaptureKit backing pixels, and secondary displays
can have negative origins.

Everything below has to be built or borrowed: bounded AX snapshot with
stable element IDs, background click delivery scoped to a window, foreground
fallback, screenshot capture with annotations, menu invocation, verification.
Peekaboo has all of it.

### 2b. Peekaboo (github.com/openclaw/Peekaboo), measured 2026-10-01

Facts from the repository, read by the Librarian today:

- **License and package.** MIT. The repository root is a Swift 6.2 package,
  `platforms: [.macOS(.v14)]`, with four library products:
  `PeekabooFoundation`, `PeekabooProtocols`, `PeekabooAutomationKit`,
  `PeekabooBridge`. Dependencies: AXorcist 0.1.11 and swift-algorithms.
  VoiceiQ's deployment target is macOS 14, so `PeekabooAutomationKit` is
  consumable as a normal remote SPM dependency.
- **Agent runtime is not consumable.** The agent loop lives in a nested
  package, `Core/PeekabooCore/Package.swift`, which depends on
  repository-relative paths (`../../Tachikoma` and others). It cannot be
  pulled from the repository URL. We write our own loop in VoiceIQCore and
  use only the automation layer. That is the right split anyway; the loop
  must speak VoiceiQ's provider stack.
- **AX snapshot.** `AXTreeCollector` traverses the matched window, not the
  app root, with defaults `maxDepth 12`, `maxElementCount 1000`,
  `maxChildrenPerNode 250`, a deadline, cycle detection, and omission of
  unreadable containers while keeping usable descendants
  (`Services/UI/AXTreeCollector.swift`, `Observation/DesktopObservationRequestModels.swift`).
- **Element IDs.** Traversal assigns `elem_N`; the presentation layer remaps
  to category-prefixed IDs (`B1` button, `T2` text input, `L3` link, `C`
  checkbox, `M` menu, `G` container, and so on), sorted top-to-bottom then
  left-to-right (`PeekabooVisualizer/.../ElementIDGenerator.swift`). IDs
  are opaque to the model; it copies what it was given.
- **Input.** `ActionInputDriver` tries AX actions first (`AXPress`,
  `AXShowMenu`, value and focus writes, scroll). `WindowRoutedPointerDriver`
  posts `CGEvent`s to one PID and window with both screen and window-local
  coordinates, revalidating PID, window ID, bounds, layer and visibility
  before each event. "The physical cursor is never warped and no activation
  API is called." Foreground mode is the explicit exception and does move
  the shared pointer (`docs/commands/click.md`).
- **Capture.** ScreenCaptureKit (`SCShareableContent`, exact-window
  filters, off-screen windows included), a CoreGraphics fallback, and
  `ObservationAnnotationRenderer` that draws outlines and ID labels on the
  screenshot, converting AX top-left bounds to AppKit drawing coordinates.
- **Electron.** No `AXManualAccessibility` in the source. Their workaround
  is an opt-in `--web-focus` retry: if a traversal finds no text fields,
  `AXPress` the dominant `AXWebArea` and traverse again
  (`docs/commands/see.md`). For Chrome content the agent prompt points at a
  Chrome DevTools MCP provider instead.
- **Dock, menus, Spaces, displays.** Dock items and context menus through
  AX; auto-hide handled by toggling the preference and restarting the Dock
  (`docs/commands/dock.md`), which is heavier than we want; menus read and
  invoked in the background by default; Spaces through private
  SpaceManagement APIs; multi-display capture keeps global logical
  coordinates and converts per display
  (`Capture/ScreenCaptureKitOperator+Display.swift`).
- **Image budget in the agent.** Max 1600 px edge, 4 MiB, one image per
  tool response, consumed images removed from context after the provider
  turn (`AgentToolMCPBridge.swift`, `PeekabooAgentService+Streaming.swift`).
  No history compaction and no prompt-cache handling in Peekaboo's own
  code.
- **Maintained.** Commits through 2026-10-01 (release tooling, background
  scroll receipts, agent model support, AXPress coordinate-click outcomes).

Dependency versus vendoring: take `PeekabooAutomationKit` as an SPM
dependency pinned to a tag, and keep a VoiceiQ `ActionExecutor` protocol in
front of it. If a needed piece sits behind private APIs we do not want in a
notarized consumer app (Spaces, the SkyLight route in the pointer driver),
replace that piece with our own AX or CGEvent code behind the same protocol.
Vendoring the whole repository is not worth it; the root package is the
stable surface.

### 2c. cua-driver, rejected

Installed 0.28.1, upstream 0.31.0, MIT, Rust, 63 MB universal binary, 55 MCP
tools, embedded-daemon mode that inherits the host's TCC grants. It has no
Swift binding and no LLM loop. Reasons it is not the action layer:

1. The user's observed failures ("cannot find the element") are the same AX
   limits a native layer hits, so cua-driver does not buy reliability.
2. It is a 63 MB sidecar in a 13 MB app (`build/release/VoiceiQ-0.5.8.dmg`),
   with nested signing and a pinned update cadence.
3. Its fallback ladder and background delivery are reproducible in Swift,
   and Peekaboo already has them.
4. Hey Clicky left it after five months for speed and window-scoped clicks.

It stays useful as a bench tool: `cua-driver get_window_state` gives a quick
second opinion on what AX exposes for an app we are debugging.

### 2d. Screenshot-only grounding

Reaches anything visible, including Metal views. Probabilistic positions, a
screenshot per step, silent misclicks. This is the last rung of the ladder,
not the first.

### 2e. Scripting fast paths

`NSWorkspace.openApplication(at:)`, URL schemes, AppleScript or JXA through
`NSAppleScript`, Shortcuts. Deterministic and layout-proof. Apple Events need
`com.apple.security.automation.apple-events` in `App/VoiceIQ.entitlements`
and a per-app Automation grant on first use. Covers "open Spotify", "new mail
to X", "set volume" without any clicks.

### Comparison

| Layer | Reach | Reliability | Latency | Extra permissions | Effort |
| --- | --- | --- | --- | --- | --- |
| Native Swift + Peekaboo | AX + pixels + background input | Good on native apps, degrades on web/Electron | Lowest | None | High, reduced by the dependency |
| cua-driver embedded | Same | Same | Low | None if bundled | Medium plus 63 MB |
| Screenshot only | Anything visible | Probabilistic | High | None | Medium |
| Scripting | What apps expose | Deterministic | Lowest | Automation per app | Low |

### The left, auto-hidden Dock

"Open Spotify" resolves a bundle ID and calls
`NSWorkspace.openApplication`. No Dock involved.

"Click the third Dock item" queries `com.apple.dock`'s AX tree. If the list
is empty because the Dock is hidden, compute which edge it occupies from
`NSScreen.visibleFrame` versus `frame` on the display that owns it, post a
mouse-moved event to that edge, wait past the reveal delay, re-query,
`AXPress`. If AX still has nothing, capture the revealed Dock and ground
visually. Never assume an x coordinate; every observation is taken at action
time from the live system.

## 3. Model side

### 3a. One model, four API formats

The custom provider offers the four formats in the reference screenshot.
What each format can carry for an agent:

| Format | Path on CLIProxyAPI | Native computer-use tool | Function tools | Images in | Stateful continuation |
| --- | --- | --- | --- | --- | --- |
| OpenAI Chat Completions | `/v1/chat/completions` | none | yes | yes | none |
| OpenAI Responses | `/v1/responses` | `tools: [{type: "computer"}]` on gpt-6-luna, gpt-6-sol, gpt-6.1-sol (developers.openai.com model pages) | yes | yes | `previous_response_id` |
| Anthropic Messages | `/v1/messages` | `computer_toolset_20260801` on the Claude 5 family | yes | yes | none |
| Google Generative AI | `/v1beta/models/{id}:generateContent` | none here; Gemini's `computer_use` tool exists only on the Interactions API, which CLIProxyAPI does not expose (*unverified beyond the docs' endpoint list*) | yes | yes | none |

The portable baseline is therefore **VoiceiQ's own function tools** on every
format: `observe`, `click(elementID)`, `type(elementID, text)`,
`press(keys)`, `scroll`, `invoke_menu(path)`, `open_app(bundleID)`,
`click_at(x, y)` on the last screenshot, `answer(text)`, `done`. One tool
schema, one system prompt, one loop. The provider's native computer tool is
an optional enhancement enabled per format and model when it is known to
pass through; it is not required for the mode to work.

Single model consequence: the same model does intent classification,
grounding and the final answer. Choose a model with image input and tool
calling. Among the IDs the user's proxy lists today, that is the Claude 5
family, gpt-6-luna, gpt-6-sol, gpt-6.1-sol and gemini-3.8-flash-high.

### 3b. CLIProxyAPI, measured on the user's server 2026-10-01

Source: help.router-for.me, github.com/router-for-me/CLIProxyAPI (MIT), the
user's `using-my-vps-server` skill, and a live `GET /v1/models` run on the
server over SSH.

- Serves OpenAI Chat Completions, OpenAI Responses, Anthropic Messages and
  Gemini formats on one port (default 8317) and translates between them.
  Function calling, streaming and image input are listed features.
- Client auth is `Authorization: Bearer <key>` with keys from
  `access.api-keys` in `config.yaml`. The management secret is a separate
  credential and never belongs in the app.
- Provider-scoped routes exist for pinning a protocol surface:
  `/api/provider/{provider}/v1/messages`,
  `/api/provider/{provider}/v1/chat/completions`,
  `/api/provider/{provider}/v1beta/models/...`. Routing still resolves from
  the model ID, so unique aliases are the way to pin a backend.
- The user's instance: version 8.0.7, base URL
  `https://bluelobster.tailb329e.ts.net:8443/v1`, 43 models on the second
  probe the same day (32 on the first). Relevant IDs: `claude-opus-5-5`,
  `claude-opus-5`, `claude-sonnet-5-5`, `claude-sonnet-5`,
  `claude-fable-5-1`, `claude-fable-5`, `gpt-6-luna`, `gpt-6-sol`,
  `gpt-6.1-sol`, `gpt-6-astra`, `gemini-3.8-flash-high`,
  `gemini-3.7-flash-high`, `gemini-3.1-pro-low`, `gemini-pro-agent`. The
  Gemini IDs carry a thinking-level suffix the proxy adds, so the model
  picker must take the ID verbatim and never derive a `PriceBook` entry
  from a prefix match alone.
- Prompt caching passthrough is **unverified**. The proxy relays the
  upstream `usage` block for the format it answers in, but whether
  `cache_control` breakpoints and `cache_read_input_tokens` survive the
  Claude Code OAuth backend has to be probed with one real request. Same
  for the `computer_toolset_20260801` beta header on `/v1/messages`.

Base URL semantics: the user enters the URL before the API path
(`https://host:8443/v1` for the OpenAI and Anthropic formats). For the Gemini
format the proxy wants the root without `/v1beta` (issue #3334, maintainer's
answer), so the format picker decides what the app appends.

### 3c. Pricing where it applies

Through CLIProxyAPI with OAuth-backed accounts there is no per-token bill,
only subscription quota. Through the dictation route the existing
`PriceBook` applies (gemini-3.8-flash $0.75 in / $0.075 cached; gpt-6-luna
$0.10 in / $0.01 cached / $0.125 cache write / $0.50 out). A custom provider
with an unknown model gets no price; the Cost pane shows tokens only.

## 4. Custom provider override, agent mode only

### Data shape

```text
AgentProviderOverride (SettingsStore, UserDefaults; key in Keychain)
  enabled: Bool
  baseURL: URL                      // entered before the API path
  format: .openAIChat | .openAIResponses | .anthropicMessages | .googleGenerativeAI
  headers: [(name, value)]          // extra request headers
  queryParameters: [String: String] // JSON object with string values
  models: [AgentModel]              // id, displayName?
  selectedModelID: String?
  apiKey: KeychainStore.Secret.agentProvider   // "agent-provider-api-key"

Resolution for a session:
  override.enabled && selectedModelID != nil  → custom endpoint
  otherwise                                   → SettingsStore().activeRoute (dictation's provider and gateway)
```

Illegal states this shape avoids: an enabled override with no model is
treated as unset, not as an error at call time; the format is an enum so the
transport cannot guess from the URL.

### Where it sits

Settings → Advanced → Experimental, the collapsible section
`ExperimentalGatewaysSection` in `App/Sources/Windows/GatewayKeySection.swift`
(line 268 onward), after the gateway keys. It is agent-only and does not
touch `ModelRoute`, `ModelGateway` or `GeminiClient`'s route selection for
dictation, translation or Ask Anything.

### UI, mapped from the reference screenshot to the app's Form style

The screenshot's layout is a stacked dark form with subtitles under fields.
VoiceiQ's settings are SwiftUI `Form` sections with `LabeledContent` rows,
`SecureField` for keys, segmented or menu `Picker`s, and footers only where
copy prevents a mistake (`TinyFishKeySection.swift`, `GatewayKeySection.swift`,
`DictationPane.swift`). The translation:

| Reference control | VoiceiQ control |
| --- | --- |
| Base URL text field with "Enter the URL before the API path" | `LabeledContent("Base URL")` with a `TextField`; footer kept, it prevents the `/v1beta` mistake |
| API Key | `SecureField` with the Keychain placeholder pattern from `TinyFishKeySection` |
| API Format radio list | `Picker("API format")` with `.radioGroup` style, four cases |
| Headers name/value rows, Add Header | A list of `HStack` rows with two `TextField`s and a remove button, plus an Add button; empty by default |
| Query Parameters JSON textarea | Same row list as headers; no JSON editor. The screenshot's textarea is a web-admin idiom, not a macOS one |
| Models, Configure | Inline list: Model ID `TextField`, optional Display Name `TextField`, Add Model; each row has a remove button |
| Model Metadata Overrides | Omitted. Those fields (token limits, tool-calling flags) exist because that product routes many agents; we have one caller and one model |
| Activate after creation checkbox | Replaced by a `Toggle("Use for Agent mode")` at the top of the section |
| (new) Selected model | `Picker("Model")` over the entered models, display name shown, ID as tag |
| (new) Save & Validate / Remove | Same two buttons as every key section; validation is `GET {base}/v1/models` for the OpenAI and Anthropic formats and `GET {base}/v1beta/models` for Gemini, with the entered headers and query parameters applied |

Validation also fills the model list from the response when the user has not
typed any IDs, which is how the 32 proxy models become a picker without
typing.

## 5. Session, window and transcript

The surface is the Ask Anything answer panel, `answerPanelSize()` in
`App/Sources/HUD/PillHUDController.swift`, `min(560, visible.width - 24)` by
`min(300, visible.height - 24)`, scrollable. Agent mode reuses that size and
the `.answer` monitors, but does not dismiss on outside click or Escape. Only
the Stop control or the mode shortcut ends the session. Pressing the shortcut
while a session is open starts listening for the next command; the window
stays.

Everything the user sees is one list, rendered in order:

```text
AgentSession
  id, startedAt, endpoint (custom or dictation route), modelID
  entries: [AgentEntry]              // append-only
    .command(text, at)               // what the user said, right-aligned like a chat
    .thought(text)                   // model intent, secondary colour
    .action(kind, target, status)    // "Click Save in TextEdit" → running / done / failed
    .observation(summary)            // "Looking at Safari, 2 windows"
    .answer(text)                    // the reply for a question
    .confirmation(request, answer)   // Allow once / Always this session / Not now
```

There is no second status surface. The newest `.action` or `.thought` is also
what the collapsed pill shows as its one-line status, so a user who collapsed
the panel still sees progress. The same list is the model's context, so the
display model and the prompt model are one structure. The session lives in
memory while the window is open and is written to history as one item at
stop, text only, no screenshots.

Placement of the controls: the Experimental section of the Dictation pane
(`DictationPane.swift`, line 120 onward, the section headed "Experimental")
gains a `Toggle("Agent mode")` and, when on, a `ShortcutRecorderRow(action:
.agent)` directly beneath it. `ShortcutAction` in
`VoiceIQCore/Sources/HotkeyEngine/ShortcutStore.swift` gains `.agent`. The
Shortcuts section at the top of the pane does not list it. The provider
override is in the Advanced pane's Experimental section (§4) because it is
key entry, and key entry lives in Advanced.

## 6. Intent handling, screen first

Both example commands share one rule: **observe before deciding**. A command
is never answered from the words alone.

```text
command arrives
  → capture: active display screenshot (≤1280 px edge, JPEG, like
    ScreenContextCollector) + frontmost app, window title, focused element,
    bounded AX summary of the frontmost window
  → one model call with the transcript, the observation and the tools
  → the model returns either answer(text) or a tool call
  → tool calls loop until answer or done; each step re-observes the
    window it acted on
```

"Explain what I am looking at": the observation is the subject. The model
answers from the screenshot and AX summary; no action. If the window is a
document longer than the screen, the model may scroll or read the AX value
before answering.

"Explain a quadratic equation to me": the system prompt instructs the model
to check whether the screen is relevant (a worksheet, a plot, a code file)
and, if so, to anchor the explanation to it; if not, to answer generally. The
model decides, with the screenshot in hand. Cost is one screenshot per
command (about 1,000 input tokens at 1280×800 on Gemini's tile rule; OpenAI
and Anthropic are of the same order), which is cheaper than a wrong answer
and a repeat.

The observation reuses `VoiceIQCore/Sources/ScreenContext/ScreenContextCollector.swift`
(ScreenCaptureKit, `maxDimension 1280`, JPEG 0.6) for the pixels and adds the
AX summary. Screen Recording denial degrades to AX-only observation and an
entry saying so.

## 7. Permissions and install flow

VoiceiQ already asks for Accessibility and Screen Recording in onboarding
(`OnboardingWindow.swift` lines 770 to 810) and checks them in
`DictationKeySection`. Microphone is granted for dictation. Agent mode adds
nothing when it stays on AX and CGEvent. Apple Events need the automation
entitlement and per-app grants only if we ship AppleScript fast paths. Input
Monitoring is not needed for posting events.

macOS 15 added a recurring reminder for apps that capture the screen outside
the system picker; expect it on every supported release (*not verified on
26.x beyond this Mac*). No external install step exists any more; the
cua-driver installer flow is gone with it.

## 8. Caching per format

Sources: ai.google.dev/gemini-api/docs/caching,
developers.openai.com/api/docs/guides/prompt-caching,
docs.anthropic.com prompt caching, openrouter.ai and vercel.com gateway
caching pages (for the dictation-route fallback).

| Format and host | Mechanism | Minimum prefix | Read price | Lifetime | Reported in |
| --- | --- | --- | --- | --- | --- |
| OpenAI Responses or Chat, direct | automatic prefix | 1,024 tokens | 10%; writes 125% | 30 min, refreshed | `usage.input_tokens_details.cached_tokens`, `cache_write_tokens` |
| Anthropic Messages, direct | explicit `cache_control` breakpoints (up to 4) | 1,024 tokens on Opus and Sonnet | 10%; writes 125% | 5 min, refreshed | `usage.cache_read_input_tokens`, `cache_creation_input_tokens` |
| Gemini, direct | implicit prefix | 4,096 tokens on 3.8 Flash | 10% | unpublished | `usageMetadata.cachedContentTokenCount` |
| Any format through CLIProxyAPI | upstream's, if the translator forwards the fields | upstream's | subscription quota, not dollars, on OAuth backends | upstream's | *unverified*; probe with two identical requests and compare `usage` |
| Dictation route via OpenRouter or Vercel | passthrough | provider's | provider's | provider's | `cached_tokens`; pin with `provider.order` or `gateway.only`, send a session-affinity ID |

Design rules that follow, independent of format:

1. System prompt and tool schemas first, byte-identical every call.
2. Transcript append-only; never rewrite earlier entries.
3. No volatile data in the prefix. The current observation goes at the tail.
4. Keep the current screenshot and the last two; drop older ones in batches
   so the prefix changes rarely. Peekaboo removes consumed images
   immediately, which is cheaper but loses visual history; we keep three.
5. On Anthropic, put one breakpoint after the tools and system prompt and one
   after the last complete turn. On OpenAI and Gemini, nothing to send.
6. `previous_response_id` on OpenAI Responses keeps the prefix stable and
   skips re-upload; it does not remove billing.

Worked estimate, 20 calls, 4,000 fixed tokens, each call adding 1,500 text
tokens and one 1280×800 screenshot, no pruning, output excluded:

| Model | Input tokens | No caching | Ideal caching |
| --- | --- | --- | --- |
| gemini-3.8-flash | 611,720 | $0.459 | $0.080 |
| gpt-6-luna | 647,000 | $0.065 | $0.013 |

Through the user's proxy these are quota, not dollars, but the same rules
stretch the quota.

Cost tracking: `PriceBook` has `cachedIn` for both dictation-route models,
`TokenUsage` reads `cachedContentTokenCount` and OpenAI `cached_tokens`.
Needed additions: Anthropic's two cache fields, a cache-write column, an
`agent` activity in `UsageStore`, and a "no price" state for custom models.

## 9. Proposed architecture

```diagram
┌───────────────┐ voice   ┌─────────────────────┐ tools  ┌─────────────────────┐
│ Expanded pill │───────▶│ AgentLoop            │──────▶│ ActionExecutor       │
│ transcript    │◀───────│ (VoiceIQCore)        │◀──────│ (protocol)           │
│ + Stop        │entries │ AgentTransport       │results│ ┌─────────────────┐ │
└───────────────┘        │  .openAIChat         │       │ │ Scripting       │ │ NSWorkspace, AppleScript
                         │  .openAIResponses    │       │ ├─────────────────┤ │
                         │  .anthropicMessages  │       │ │ NativeExecutor  │ │ PeekabooAutomationKit:
                         │  .googleGenerativeAI │       │ │                 │ │ AX snapshot, IDs,
                         └─────────────────────┘       │ │                 │ │ background CGEvent,
                                  ▲                     │ └─────────────────┘ │ SCK capture + annotate
                         ┌────────┴────────┐            └─────────────────────┘
                         │ Endpoint resolver│  custom override, else dictation route
                         └─────────────────┘
```

Core shapes first: `AgentSession` and `AgentEntry` (§5);
`AgentProviderOverride` (§4); `ActionTarget` as an enum
(`app(bundleID)`, `element(snapshotID, id)`, `point(displayID, x, y)`,
`menu(path)`, `script(bundleID, source)`); `ActionOutcome`
(`done`, `unverifiable`, `failed(reason)`, `needsConfirmation(reason)`).

Where things live:

- `VoiceIQCore/Sources/AgentEngine/`: `AgentSession`, `AgentLoop`,
  `ActionExecutor`, `AgentTransport` with one adapter per format,
  `AgentToolSchema` (the single tool list rendered per format),
  `AgentProviderOverride`.
- `App/Sources/Agent/`: `NativeExecutor` (wraps `PeekabooAutomationKit`
  plus our Dock and display code), `ScriptingExecutor`, `AgentPanelView`,
  `AgentPillContent`.
- `GatewayKeySection.swift`: `AgentProviderSection` inside
  `ExperimentalGatewaysSection`. `KeychainStore.Secret.agentProvider`.
- `DictationPane.swift`: Agent mode toggle and shortcut row in the
  Experimental section. `ShortcutStore`: `.agent`.
- `project.yml`: the `PeekabooAutomationKit` package dependency.
- `UsageStore`: `agent` activity, cache-write and Anthropic cache columns.

Fallback ladder in `NativeExecutor`, applied before the model is told an
action failed, each rung one transcript entry: AX action on the element ID
→ menu or keyboard shortcut → background CGEvent at the element's bounds →
foreground click → `click_at` on the annotated screenshot chosen by the
model.

Open decisions, each with a default:

1. **Native computer tools.** Default: function tools only in the first
   build; add the OpenAI `computer` and Anthropic `computer_toolset` paths
   after a measured task set shows the baseline's grounding is the limit.
2. **Confirmation policy.** Default: Hey Clicky's three-way prompt at the
   first state-changing action per session, plus always-confirm for send,
   pay, delete, share, log in, accept terms, CAPTCHA.
3. **Peekaboo private-API pieces.** Default: do not call the Spaces or
   SkyLight paths; use the public PID-targeted CGEvent route and skip
   cross-Space windows with an explanatory entry.
4. **Screenshot retention in context.** Default: current plus last two.
5. **Default model when the override is unset.** The dictation route's
   writing model (`gemini-3.8-flash` or `gpt-6-luna`).

## 10. Risks

- The user's cua-driver failures are not root-caused. Before building the
  executor, record ten failing commands against both `cua-driver
  get_window_state` and a Peekaboo `see` run and classify them (Electron,
  hidden Dock, other Space, wrong display, stale snapshot). The ladder
  targets those classes; the recording decides the order of work.
- Every step is a model round trip. The only in-repo measurement is 2.4 s
  for a one-call dictation on `gemini-3.8-flash` (`PromptV1.swift`). A step
  with a screenshot and an AX summary through a proxy to an OAuth backend is
  unmeasured. Batched actions and scripting fast paths are the mitigation.
- CLIProxyAPI passthrough of caching fields and of the Anthropic computer
  tool is unverified. Two probes settle both.
- Peekaboo's root package is `swift-tools-version` 6.2 in Swift 6 language
  mode. VoiceiQ builds with `SWIFT_VERSION: "5.10"` (`project.yml`) and
  `VoiceIQCore/Package.swift` is tools-version 5.10, on Xcode 27.0. A
  package can depend on a newer-language-mode package as long as the
  toolchain is new enough, but any `Sendable` type crossing the boundary
  will surface Swift 6 warnings on our side. Confirm with a throwaway
  `swift package resolve` before committing to the dependency.
- Screen capture reminders on macOS 15+ interrupt long sessions.
- Prompt injection through screen content: the system prompt names the
  spoken command as the only instruction source, and screen text is
  labelled as data.
