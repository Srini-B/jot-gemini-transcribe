# 2026-10-02: Per-request sessions, lost-connection retry, MAI Clean style, copy recovered on by default

## Why

- **False "offline":** on 13:10 IST, an ElevenLabs request reused an idle HTTP/3 connection, received a QUIC stateless reset, and failed in 42 ms with -1005. The app mapped that to `.offline`, queued the dictation and said "You're offline" while Wi-Fi was up.
- **Stalls:** earlier OpenAI cleanup stalls also ran on HTTP/3, one on a connection reused after 134 s idle.
- **MAI fillers:** MAI Transcribe 2 was getting Azure's default `verbatim` style, so every "uh" reached the text whenever cleanup did not run.

## QUIC / HTTP/3 findings

- **No off switch:** URLSession has no public API to disable HTTP/3 for a session or request.
  - Apple DTS (forums thread 796780): "There's not a good way to disable QUIC for a specific URLSession."
  - `assumesHTTP3Capable` only opts in.
  - The QUIC idle timeout cannot be configured through URLSession (forums thread 771945); only Network.framework exposes it.
- **How URLSession finds HTTP/3** (TN3102): a DNS HTTPS record or an `Alt-Svc` header.
  - DNS on 2026-10-02 (`dig -t TYPE65`): no HTTPS record for api.openai.com, api.elevenlabs.io or generativelanguage.googleapis.com. openrouter.ai advertises `alpn=h2` only, and ai-gateway.vercel.sh is a CNAME.
  - So HTTP/3 came only from `Alt-Svc`, which each ephemeral session remembers on its own.
- **Probe:** a new ephemeral session per request used `h2` on all five hosts, 3 of 3 times each, run on the MacBook. A shared session reused its connection.
- **The reset:** CFNetwork's log for the reset shows `idempotent(N) ... can retry(N)`, so URLSession never retries a POST itself.

## Change

- **Transport** (`GeminiClient+Transport.swift`):
  - `GeminiClient.post` sends every model request through `perform`, which opens a new ephemeral `URLSession` per request. Each request starts on TCP + HTTP/2 and never reuses an idle connection. The measured cost is `connectMs` 57–59.
  - `URLError.networkConnectionLost` gets one immediate attempt on a new session with the remaining deadline. A second loss is still `.offline`.
  - The response is returned once, so a retried non-idempotent POST may be billed twice but cannot be shown twice.
  - Transcription timeouts retry at once; server errors retry after 0.5 s.
  - The cleanup hedge keeps its second attempt, which now uses its own session like every request.
- **Request IDs and metrics** (`Support/TransportLog.swift`): every attempt carries `X-Client-Request-Id`, identical across a retry. It is logged at notice level and appended to `transport.jsonl` in Application Support, rotating at 2 MB. Fields: protocol, reuse, connect time, time to first byte, total time, body bytes, status and outcome.
- **MAI style** (`MAITranscribeStyle`, `SettingsStore.maiTranscribeStyle`, default Clean, Settings → Advanced → "Transcript style" when MAI is selected):
  - `GeminiClient.maiAzureOptions` builds the payload for dictation and meetings.
  - With Clean, the filler fallback no longer runs for MAI.
- **Copy recovered dictations:** on by default, read as `object(forKey:) as? Bool ?? true`. An explicit Off is kept and nothing is written for installs that never touched it.

## Live MAI probe (signed, notarized build on the Mac mini, real MacBook recordings)

| Gateway | Field | Style | "uh" kept (5.6 s / 48 s clip) |
|---|---|---|---|
| OpenRouter | none | default | 1 / – |
| OpenRouter | `provider.options.azure.modelOptions.transcribeStyle` | clean | 1 / 13 (ignored, 200) |
| OpenRouter | `provider.options.azure.transcribeStyle` | clean | 1 / – (ignored, 200) |
| OpenRouter | `provider.options.azure.enhancedMode.modelOptions.transcribeStyle` | clean | **0 / 0** |
| OpenRouter | same | verbatim | 1 / – |
| OpenRouter | same + `diarization` + `timestamps` | clean | 0, accepted |
| Vercel | none | default | 1 / – |
| Vercel | `providerOptions.azure.transcribeStyle` | clean | **0 / 0** |
| Vercel | same | verbatim | 1 / – |
| Vercel | `providerOptions.azure.modelOptions.transcribeStyle` | clean | 400 "invalid azure provider options" |

## Verification

See the thread report: `swift test`, the iOS build, the signed and notarized build installed on the Mac mini, a live MAI Clean run on both gateways, copy-on-recovery by default, and `transport.jsonl` contents.

## Residual limitations

- A server that accepts a request and never answers can still stall it. The cleanup hedge and the transcription timeout retry bound the wait.
- Retries after a lost connection can be billed twice.
- Key validation GETs, agent mode and TinyFish keep their own sessions.
- If a host starts publishing an HTTPS DNS record with `h3`, a fresh session could pick HTTP/3 again. `networkProtocol` in `transport.jsonl` would show it.
