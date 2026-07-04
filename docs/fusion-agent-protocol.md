# Fusion Agent Protocol

> **2026-07-03**: the project now targets the hardened fork
> `beforeugone520/wand-agent` (commit `2974ee3`) as the default VM backend.
> Fork behavior differences from stock `ystyle/wand-agent`:
> binary frames always route to the PTY and only text frames are parsed as
> control JSON; `Authorization: Bearer <token>` is the preferred auth (query
> `?token=` still accepted); JSON `ping` is answered with `pong`; the agent
> emits `{"type":"exit"}` when the shell exits and never injects
> bracketed-paste markers; `fork` returns an `unsupported` error — open one
> WebSocket per terminal; `--host/--port/--max-sessions` are enforced.
> FusionTerm sends both the Bearer header and the query token, so it works
> against either backend.


## Purpose

Fusion Agent is the preferred transport for FusionTerm's Fusion VM path. The
HarmonyOS app connects to a small agent running inside the Fusion Development
Engine Linux VM. The agent owns Linux PTY creation and process lifecycle; the
HarmonyOS app owns UI state, terminal rendering, profiles, and reconnection.

This is intentionally narrower than a general SSH client. SSH remains available
as a fallback and later advanced mode, but the first product path should make the
known Fusion VM feel native and low-friction.

## Relationship To wand-agent

`ystyle/wand-agent` is the compatibility target for the current milestone:

- WebSocket endpoint creates one PTY session per terminal connection.
- Binary frames carry terminal input and output bytes.
- Text frames carry JSON control messages such as resize, cwd, fork, terminate
  (when advertised by a hardened agent), ping, and errors.
- The PTY environment advertises `TERM=xterm-256color` and
  `COLORTERM=truecolor`.

FusionTerm should speak that wire format directly, then harden the VM-side agent
later as a project-owned fork if needed.

## Default Endpoint

Development default:

```text
ws://172.16.100.2:8765/ws?token=harmonyterm&cols=80&rows=24
```

The default matches `ystyle/wand-agent`'s openEuler container address, port, and
prototype token. If a device build exposes the VM through another gateway
address, change the single app constant rather than reintroducing a DNS-only
host name.

Connection query parameters:

```text
token=<bearer token>
cols=<terminal columns>
rows=<terminal rows>
cwd=<optional initial directory>
shell=<optional shell path>
```

Production should prefer `wss://` or an SSH tunnel when traffic leaves the
trusted VM bridge network.

## Frame Model

Binary frames are raw terminal bytes:

- app to agent: keyboard input, paste data, quick-key escape sequences;
- agent to app: PTY output, including ANSI/VT sequences.

Text frames are UTF-8 JSON control messages:

```json
{
  "type": "message-type"
}
```

The app must pass binary server frames directly to `TerminalController.feed()`.
The app must send terminal input bytes from `TerminalController.write()` as
binary client frames.

## Session Start

There is no app-side `hello` frame. Opening `/ws` creates the PTY session. After
the WebSocket opens, FusionTerm sends a current-directory query:

```json
{
  "type": "cwd"
}
```

The agent replies with the current directory when available:

```json
{
  "type": "cwd",
  "dir": "/home/user"
}
```

FusionTerm still accepts a future `ready` frame from a hardened fork, but it must
not send unknown JSON controls to stock `wand-agent`, because unknown text frames
are forwarded to the PTY as terminal input by that prototype.

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

The agent resizes the PTY. No response is required unless resize fails.

### Working Directory

App to agent:

```json
{
  "type": "cwd"
}
```

Agent to app:

```json
{
  "type": "cwd",
  "dir": "/home/user/project"
}
```

The agent may also push `cwd` changes when it detects a new process working
directory.

### Fork

App to agent:

```json
{
  "type": "fork",
  "cwd": "/home/user/project"
}
```

Agent to app:

```json
{
  "type": "forked",
  "id": "new-session-id"
}
```

The current app exposes the helper method but does not yet add session tabs in
the UI.

### Heartbeat

Either side may send:

```json
{
  "type": "ping",
  "ts": 1783075200000
}
```

Stock `wand-agent` uses `ping` as the reply shape as well, so FusionTerm replies
with the same `type` and timestamp. A future project fork may also introduce
`pong`; the app treats `pong` as a no-op for compatibility.

The app should consider the connection stale after two missed heartbeat
intervals.

### Terminate

App to hardened agent, only when the agent advertises a terminate capability in
its `ready.capabilities` list:

```json
{
  "type": "terminate"
}
```

The agent should terminate the PTY process group, flush remaining output, emit
`exit` when possible, and close the WebSocket. FusionTerm does not send this
JSON control to stock `wand-agent` because unknown text frames may be forwarded
to the PTY. For stock compatibility, closing a tab sends terminal bytes for
Ctrl-C followed by `exit` before closing the socket.

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

After `exit`, the agent closes the WebSocket once buffered PTY output has been
sent.

### Error

Agent to app:

```json
{
  "type": "error",
  "error": "failed to start /bin/bash"
}
```

The app also tolerates `message` and `code` fields from a hardened fork. The
status bar should show a short safe string and keep detailed logs for
diagnostics.

## Authentication

Prototype mode may use a bearer token because the agent is expected to run on a
trusted VM bridge network. Do not ship a long-lived URL query token as the final
design.

Preferred progression:

1. Prototype: token in query string for fast local testing.
2. Milestone: token in `Authorization: Bearer <token>` or WebSocket subprotocol.
3. Hardened: short-lived pairing token minted from the VM management channel.
4. Networked: `wss://` or SSH tunnel when traffic is not isolated to the VM
   bridge.

The agent should bind to the narrowest practical address. Avoid exposing it on a
public interface unless TLS and authentication are configured.

## Agent Runtime Requirements

The agent must:

- start one PTY per WebSocket connection;
- set `TERM=xterm-256color` and `COLORTERM=truecolor`;
- resize the PTY when receiving `resize`;
- clean up the process group when the socket closes;
- avoid logging terminal input or bearer tokens.

A hardened project fork should additionally bound max sessions, report shell
exit state, and expose version/build info in startup logs.

## HarmonyOS App Integration

Add a new ArkTS transport next to the current native driver:

```text
entry/src/main/ets/drivers/FusionAgentDriver.ets
```

`FusionAgentDriver` should:

- use HarmonyOS WebSocket APIs from NetworkKit;
- map terminal input to binary WebSocket frames;
- map binary output frames to `TerminalController.feed()`;
- send `cwd` after the socket opens;
- send `resize` on terminal size changes;
- update app status from `cwd`, `forked`, `ready`, `exit`, and `error`;
- reconnect only after an explicit user action for the first milestone.

Keep `libghostty_ohos` transport-neutral. Do not move Fusion Agent assumptions
into the renderer HAR.

## First Implementation Milestone

1. Run stock `ystyle/wand-agent` or a hardened fork inside the Fusion
   Development Engine Linux VM.
2. Add `FusionAgentDriver.ets` and a profile mode for the Fusion Development
   Engine VM bridge at `ws://172.16.100.2:8765/ws`.
3. Remove the app-side custom `hello` handshake and use only wand-agent controls:
   `resize`, `cwd`, `fork`, and `ping`.
4. Send terminal input and quick-key sequences as binary WebSocket frames.
5. Make the `VM` button use Fusion Agent by default.
6. Keep SSH as a fallback action in the connection panel.
7. Verify with 256-color, truecolor, resize, Ctrl-C, Ctrl-D, Tab, and paste
   smoke tests.
