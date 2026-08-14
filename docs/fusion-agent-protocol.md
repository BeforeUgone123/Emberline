# Fusion Agent Protocol

## Purpose

Fusion Agent is Emberline's primary transport into the Fusion Development
Engine Linux VM. The VM-side agent owns the Linux PTY and process lifecycle;
the HarmonyOS app owns tabs, UI state, rendering, reconnection, profiles, and
fallback transports.

The default backend is the hardened `beforeugone520/wand-agent` fork (based on
`ystyle/wand-agent` v0.2.3). Emberline keeps enough compatibility for the stock
wire format, but new product behavior must target the hardened fork.

Keep the transport in `entry`:

```text
entry/src/main/ets/drivers/FusionAgentProtocol.ts
entry/src/main/ets/drivers/FusionAgentDriver.ets
```

Do not move VM assumptions or WebSocket orchestration into `libghostty_ohos`.

## Development Endpoint

The current development default is:

```text
ws://172.16.100.2:8765/ws?token=harmonyterm&cols=80&rows=24
```

Constants live in `FusionAgentProtocol.ts`:

- host `172.16.100.2`;
- port `8765`;
- path `/ws`;
- token `harmonyterm`;
- initial grid `80x24` until the renderer reports its real size.

Supported query parameters are `token`, `cols`, `rows`, optional `cwd`, and
optional `shell`. `secure: true` changes the scheme to `wss`.

The published default token and plain `ws://` endpoint are for a trusted local
VM bridge only. Production exposure requires per-install pairing, secure
credential storage, Authorization-only authentication, and `wss://` or a
protected tunnel. See `code-review-2026-07-10.md` (CR-003).

## Authentication Compatibility

When a token is configured, Emberline currently sends it twice:

1. `Authorization: Bearer <token>` for the hardened fork;
2. `?token=<token>` for stock wand-agent compatibility.

Do not log the URL, token, Authorization header, or terminal input. Removing the
query token is part of the production pairing/transport work; doing it before
stock compatibility is intentionally dropped would be a protocol change.

## Frame Model

Binary frames contain raw terminal bytes:

- app to agent: native keyboard and paste input encoded as UTF-8;
- agent to app: PTY output, including ANSI/VT control sequences.

The client preserves an incomplete UTF-8 tail across WebSocket frames before
feeding text to `TerminalController`. Text frames are UTF-8 JSON controls with a
required `type` field:

```json
{
  "type": "message-type"
}
```

The hardened fork routes binary frames only to the PTY and text frames only to
the control parser. Stock wand-agent may forward unknown text controls into the
PTY, so the app must not invent controls without capability/compatibility review.

## Connection Start

Opening the WebSocket creates one PTY session. Emberline does not send an app
`hello` frame. On `open`, the client:

1. marks the socket connected;
2. resets the reconnect attempt counter;
3. reports the connected endpoint to the tab;
4. sends `{"type":"cwd"}`.

The hardened fork may send an optional `ready` frame:

```json
{
  "type": "ready",
  "sessionId": "session-id",
  "cwd": "/home/user",
  "capabilities": ["terminate"]
}
```

Emberline uses `ready.capabilities` only for guarded controls such as remote
termination. It does not require `ready` before accepting PTY output.

## Control Messages

### Resize

App to agent:

```json
{
  "type": "resize",
  "cols": 120,
  "rows": 34
}
```

The app sends resize only after the grid actually changes and clamps both values
to positive integers.

### Working Directory

App query:

```json
{
  "type": "cwd"
}
```

Agent response/push:

```json
{
  "type": "cwd",
  "dir": "/home/user/project"
}
```

The app also accepts `cwd` instead of `dir`. The current directory can become
the tab title and the base for image-paste path decisions.

### Heartbeat

Incoming stock-compatible ping:

```json
{
  "type": "ping",
  "ts": 1783075200000
}
```

Emberline replies with the same `type` and timestamp and also originates a JSON
`ping` every 25 seconds while the socket is connected. Incoming `pong` is
accepted as a no-op. This keeps idle traffic below the hardened Agent's usual
30-second read interval, but the stock-compatible client still cannot require a
`pong`, track a missed reply deadline, or reattach the old PTY after a real socket
loss. Those remaining limits keep CR-007 open until device testing and a durable
session protocol exist.

### Fork Compatibility Helper

The protocol helper can send:

```json
{
  "type": "fork",
  "cwd": "/home/user/project"
}
```

and parse a `forked` reply. The hardened project fork intentionally reports
`unsupported`; Emberline's visible tabs use independent WebSocket connections,
not the fork control. Do not build tab lifecycle on this helper.

### Terminate

Only when `ready.capabilities` contains `terminate`, `session.terminate`, or
`control.terminate`, an explicit remote-session termination may send:

```json
{
  "type": "terminate"
}
```

Closing/detaching a normal tab is passive. The app never falls back to injecting
Ctrl-C or `exit`, because that could interrupt a foreground task inside tmux.

### Exit

Agent to app:

```json
{
  "type": "exit",
  "status": 0,
  "signal": "",
  "message": "shell exited"
}
```

On `exit`, the app closes the socket before reporting the final label so stale
input cannot be written into a dead shell.

### Error

Agent to app:

```json
{
  "type": "error",
  "code": "start-failed",
  "error": "failed to start /bin/bash"
}
```

The client accepts `error`, `message`, and `code`. Current control-error state
and socket teardown still need one atomic transition (see the additional risks
in the dated code review).

### Upload Relay (Hardened Fork)

App to agent:

```json
{
  "type": "upload-relay",
  "relayId": 1,
  "src": "/shared/path/image.png",
  "target": "user@remote-host",
  "dir": "/tmp/emberline-paste"
}
```

Agent reply:

```json
{
  "type": "upload-relay-result",
  "relayId": 1,
  "ok": true,
  "path": "/tmp/emberline-paste/image.png"
}
```

On failure the reply sets `ok: false` and provides `error`. The app allows one
or more requests keyed by numeric `relayId`, uses a 35-second client deadline,
and rejects known requests during deliberate connection teardown. Per-session
credential isolation and reconnect-generation cleanup remain open review items.

The hardened agent constrains the source to its shared directory, limits file
size, validates target/directory arguments, and invokes `scp` without a shell.

## Reconnection And Teardown

- `connect()` arms automatic recovery and stores the last endpoint.
- After an initial failure or a previously connected socket drop, retry delay is exponential:
  1, 2, 4, 8, 16, then at most 30 seconds.
- Typing while a retry timer is waiting cancels the delay and retries now; the
  triggering input is not queued.
- Explicit disconnect, passive detach, and clean `exit` disarm retries.
- Every event handler is tied to its own socket instance so late callbacks from
  an old socket cannot update a replacement session.
- `connect()` and `send()` synchronous errors, Promise rejection, and resolved
  `false` results all enter the same generation-guarded failure transition.

A transport whose NetworkKit socket remains falsely healthy can still evade this
recovery path because stock wand-agent does not promise a `pong`. Do not describe
the current client as fully self-healing until missed-heartbeat detection and
durable PTY reattachment are specified and device-tested.

## Agent Runtime Requirements

The VM-side agent must:

- create one PTY per WebSocket connection;
- set `TERM=xterm-256color` and `COLORTERM=truecolor`;
- apply `resize` to the PTY;
- serialize WebSocket writes;
- clean up the process group when the socket/session is terminated;
- avoid logging input or credentials;
- bound concurrent sessions and enforce authentication.

Recommended development launch:

```sh
wand-agent --host 172.16.100.2 --token harmonyterm
```

## Verification Gate

Source checks cover protocol URL construction, controls, driver wiring, default
target, auto-connect structure, and Agent setup documentation. A release still
requires a DevEco/device pass for:

- authentication success/failure;
- 256-color and truecolor output;
- resize, Ctrl-C, Ctrl-D, Tab, IME, and paste;
- first-connect failure, backoff, half-open timeout, and foreground recovery;
- multi-tab isolation and upload-relay generation handling;
- background `taskKeeping` plus foreground screen-on behavior.
