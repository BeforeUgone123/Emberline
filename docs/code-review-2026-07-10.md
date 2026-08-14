# Emberline Code Review — 2026-07-10

## Status

This is a read-only review of commit `cbc26ae` (`feat: prepare Emberline
release polish`). No production code was changed during the review. The findings
below are intentionally recorded for a later repair pass.

The review covered:

- the Fusion Agent ArkTS transport and protocol;
- session, multi-window, persistence, notification, and background-task state;
- native PTY, SSH, SFTP, N-API, renderer, and XComponent lifecycles;
- HarmonyOS manifests, signing/build configuration, third-party dependencies;
- the existing `tools/check-*.mjs` quality gate.

Line numbers below refer to reviewed commit `cbc26ae`; use the finding IDs and
named symbols when auditing the current tree.

## 2026-07-18 Reconciliation

| Finding | Dev status | Current disposition |
| --- | --- | --- |
| CR-001–CR-004 | Unresolved | Still release-blocking. |
| CR-005 | Resolved; product decision superseded | The 2026-08-01 one-shot deploy prompt intentionally restores automatic onboarding, while guide/editor/inspector state continues to block terminal input and restore focus safely. |
| CR-006–CR-010 | Unresolved | Native I/O/lifecycle, Agent recovery, renderer disposal, and libssh2 lifetime still need repair. |
| CR-011 | Resolved in source; device gate pending | Owner context, transition generation, system task events, and lifecycle reconciliation are implemented; long-lock survival still needs device proof. |
| CR-012 | Resolved in dev | Quick-key state, builder, helper, and icons remain removed. A minimal preferences-backed onboarding store returned only for the explicit 2026-08-01 deploy-prompt decision. |
| CR-013 | Partially resolved | README now uses a fail-fast loop and the gate has 33 scripts; the ignored signing-profile dependency and lack of executable integration/device tests remain. |
| CR-014 | Partially resolved | Dev and release are separate worktrees/bundle identities; signing files remain machine-specific and release signing still needs clean-machine verification. |

The 2026-07-18 UI and lifecycle pass did not change renderer, native driver,
Fusion Agent driver, SSH/SFTP, or release-worktree code. Do not infer that the
remaining findings were fixed by the UI work.

All 33 source-structure scripts passed in the current dev worktree on
2026-07-18. This does not close CR-013: a clean clone still lacks the ignored
signing-profile fixture, and no HAP/integration/device test ran here.

## Release Blockers

### CR-001 — Critical — Vulnerable libssh2 is statically linked

`tools/fetch-third-party.sh:31` pins `libssh2-1.11.1`, and
`entry/src/main/cpp/CMakeLists.txt:41,60` builds and statically links it into
`libfusion_terminal_driver.so`.

The exact tag commit, `a312b43325e3383c865a87bb1d26cb52e3292641`, is listed
by OSV as affected by multiple vulnerabilities, including the transport
out-of-bounds write [CVE-2026-55200](https://osv.dev/vulnerability/CVE-2026-55200)
and pre-authentication denial of service
[CVE-2026-55199](https://osv.dev/vulnerability/CVE-2026-55199). The former is
reachable from hostile SSH transport data before user authentication.

**Required before release:** compile SSH/SFTP out, or pin and verify an upstream
revision containing every applicable fix. Add commit-based vulnerability
scanning rather than relying on a movable release tag.

### CR-002 — Critical — SSH and SFTP do not authenticate the server

`entry/src/main/cpp/ssh/ssh_session.cpp:90-99` performs the handshake and then
sends the password while explicitly skipping host-key verification. The
one-shot SFTP path repeats the same sequence at
`entry/src/main/cpp/terminal_driver.cpp:813-820`.

A man-in-the-middle endpoint can collect the SSH password and observe or modify
terminal and image-upload traffic.

**Required before release:** extract a SHA-256 server fingerprint immediately
after the handshake, compare it with a pinned/accepted trust record, and only
then authenticate. Interactive SSH and SFTP must share the same verifier.

### CR-003 — High — Production Agent authentication is public and exposed

`entry/src/main/ets/drivers/FusionAgentProtocol.ts:5` hard-codes the published
token `harmonyterm`. `buildFusionAgentUrl()` places it in a `ws://` query string,
`FusionAgentDriver.ets:207-215` also sends it as a Bearer header, and
`ConnectionStore.ets:36-40` persists it in ordinary Preferences.

An unchanged Agent can be accessed by any bridge-network client that knows the
repository default. URL queries can reach diagnostics and proxies, while plain
WebSocket traffic exposes the token and terminal stream to a network observer.

**Required before production exposure:** per-install pairing with a strong
random token, HarmonyOS secure credential storage, Authorization-only auth for
the hardened Agent, and `wss://` or a protected tunnel outside a strictly
isolated VM bridge.

## High-Priority Correctness Findings

### CR-004 — Image paste can upload to another tab's SSH host

SSH connection details are not retained by `TerminalSessionHandle`.
`Index.ets:2747-2763` connects the active tab from page-global draft fields, and
`Index.ets:3002-3017` later uploads images using the *current* global
`draftHost`, `draftUser`, and `draftPassword`.

After configuring tab B, pasting an image in the older tab A can send that image
to B and paste B's remote path into A. Store an in-memory upload profile on each
session and bind asynchronous completion to a session/transport generation.

### CR-005 — First-launch modal leaves the terminal input-active

`Index.ets:1404-1407` displays the Agent guide, but the `TerminalSurface.active`
predicate at `Index.ets:1423-1425` and `terminalInputActive()` at
`Index.ets:1177-1179` do not include `agentGuideOpen`.

Physical keyboard, mouse, and axis events can reach the live terminal behind the
modal, and delayed focus timers can refocus it. Every modal must participate in
the native input-block predicate; focus should be restored only after dismissal.

**2026-08-01 status — resolved:** the automatic guide now intentionally opens
once for wand-agent setup. `terminalInputActive()` and
`TerminalSurface.active` include the guide, editor, inspector, and background
state; dismissal returns focus to the active terminal. Structural checks pin
both the one-shot persistence and input-blocking behavior.

### CR-006 — Nonblocking PTY/SSH writes silently discard input

`SSHSession::write()` breaks on `LIBSSH2_ERROR_EAGAIN` and returns success with
bytes still pending (`ssh_session.cpp:183-195`). Local PTY descriptors are
nonblocking (`pty_handler.cpp:220-229`), while
`WriteToLocalPtyLocked()` drops the unwritten tail on any error except `EINTR`
(`terminal_driver.cpp:333-348`).

Large paste operations or temporary backpressure can corrupt a command without
warning. Both paths need an ordered pending-byte queue, writable readiness, and
explicit failure propagation.

### CR-007 — Agent recovery and durable session continuity (partially repaired 2026-08-05)

The client now sends a stock-compatible JSON `ping` every 25 seconds. Initial
`error`/`close`, synchronous failures, Promise rejection, and resolved `false`
results from NetworkKit `connect()`/`send()` all enter one socket-generation-
guarded failure transition and schedule exponential retry.

The remaining release blocker is narrower but fundamental: stock compatibility
does not guarantee a `pong`, so the client does not yet close a socket after a
missed application-level deadline. More importantly, one WebSocket still owns
one PTY; any real reconnect creates a fresh shell instead of reattaching the old
PID and scrollback. Device lock testing and a durable session-ID/reattach
protocol are required before claiming self-healing session continuity.

### CR-008 — Native EOF never reaches ArkTS connection state

SSH EOF only sets native `m_connected=false` at `ssh_session.cpp:207-242`.
Local PTY EOF/read failure leaves the read loop without a lifecycle callback at
`terminal_driver.cpp:302-331`. ArkTS marks a successful start as connected and
never receives the later exit.

Tabs, notifications, input routing, and keep-alive can therefore remain active
after the transport is dead. Add a generation-tagged native status TSFN and
perform one atomic terminal transition/cleanup per exit.

### CR-009 — Closing tabs leaks Terminal hosts and scrollback

`libghostty_ohos/src/main/cpp/napi_init.cpp:3724-3773` keeps every
`TerminalHost` in process-global maps. `OnSurfaceDestroyed()` at lines 928-943
releases the renderer/window but deliberately retains the `Terminal`; no final
erase exists. Surface IDs are monotonic, so a closed tab is never reused.

Repeated high-output tab creation and closure can grow memory until process
termination. Add explicit final `destroyHost(surfaceId)` disposal that is
separate from temporary surface destruction used by rebind/tear-out.

### CR-010 — libssh2 global initialization races across workers

Each SSH connect calls `libssh2_init()` at `ssh_session.cpp:42`; every SFTP
upload does so at `terminal_driver.cpp:773`. libssh2 documents this global state
as non-thread-safe, yet multiple tab/upload workers can enter concurrently.
Several handshake/EOF failure paths also skip the matching `libssh2_exit()`, and
SFTP never calls it.

Initialize the library once process-wide with `std::call_once`, and release it
once during module/process cleanup rather than per session.

## Medium-Priority Findings

### CR-011 — Keep-alive can stop while a session is live

If a session reconnects while `stopBackgroundRunning()` is awaiting,
`noteSessionActive()` sees `running=true` and does not start. The old stop then
finishes and unconditionally sets `running=false` (`KeepAliveManager.ets:148-168`)
without rechecking `activeCount`. Track owner context and transition generation,
then restart after stop whenever `activeCount > 0`.

**2026-08-02 status — resolved in source, device lock test pending:** continuous
task start/stop now records its owner context and transition generation. A stop
completion rechecks `activeCount` and restarts through the most recent live
window context. The manager also subscribes to cancel/suspend/active events and
reconciles protection on both background and foreground lifecycle edges.

### CR-012 — The prohibited on-screen quick-key bar is present again

The 2026-07-03 product decision in `AGENTS.md` prohibits a soft key row on the
physical-keyboard-first target. `Index.ets:1508-1522` still exposes the keyboard
toggle, and `Index.ets:3031-3103` mounts Esc, Tab, Ctrl-C, copy/paste, arrows, and
page keys. Remove the toggle, state, builder, and accessory-key helper together.

**2026-08-01 status — resolved:** `accessoryVisible`, `buildAccessoryBar()`,
`sendAccessoryKey()`, and keyboard/help top-level icons remain absent. A small
`OnboardingStore.ets` now persists only the explicit first-launch wand-agent
prompt; it does not restore any quick-key UI. The physical-keyboard-only
decision remains covered by `check-harmony-native-workbench.mjs` and the
updated IME check.

### CR-013 — The quality gate is not clean-clone safe

The README command uses `node "$f" || echo ...`, which swallows every non-zero
exit. `tools/check-terminal-paste.mjs:6` also reads
`docs/粘贴板Debug.p7b` unconditionally even though `docs/*.p7b` is ignored.

All 30 checks pass in the current local working tree, but a `git archive HEAD`
copy passes 29 and fails `check-terminal-paste.mjs` with `ENOENT`. Provide one
fail-fast runner, replace the signing artifact with a sanitized tracked fixture,
and add compilation, native behavioral, integration, and device tests. Most
current checks are source-regex assertions rather than executable behavior.

**2026-07-18 status — partially resolved:** README now documents a fail-fast
loop and the current tree has 33 checks. `check-terminal-paste.mjs` still reads
the ignored `docs/粘贴板Debug.p7b` file unconditionally, so clean-clone safety is
not fixed.

### CR-014 — Signing configuration is machine-specific and secret-bearing

`build-profile.json5:14,25-39` binds all build modes to one signing identity,
commits protected password blobs, and references absolute certificate, profile,
and keystore paths that are absent from a clean clone. Debug and release should
use separate configs, with real signing material injected locally or by CI.
Choose the permanent Emberline bundle identity before store publication;
`AppScope/app.json5` still uses `com.preview.fusionterm` and vendor `preview`.

**2026-07-18 status — partially resolved:** the dev worktree now uses
`com.preview.fusionterm.debug`, `Emberline Dev`, and a debug signing config;
`main` remains in a separate release worktree with `com.preview.fusionterm`.
Both profiles still contain machine-specific absolute paths, so reproducible
signing and clean-machine release verification remain open.

## Additional Risks Confirmed At Commit `cbc26ae`

- Unexpected Agent `close`/`error` does not immediately reject pending relay
  requests; they survive for 35 seconds and can cross a reconnect generation
  (`FusionAgentDriver.ets:362-375,403-431`).
- An Agent control `error` reports ArkUI disconnected without clearing the
  driver's internal `connected` state or closing the socket
  (`FusionAgentDriver.ets:467-469`). Input can continue while the UI and
  keep-alive say the connection is dead.
- Settings can be edited before their asynchronous Preferences stores are
  initialized. Early `save()` calls silently return, and a later load can
  overwrite the new values (`ConnectionStore.ets:32-41`,
  `AppearanceStore.ets:56-70`, `Index.ets:3431-3478`).
- Notification IDs use per-window session IDs, so different windows overwrite
  each other's task notifications (`Index.ets:550,1302`).
- `EntryAbility.ets:75` hides an API-14 `setDecorButtonStyle()` call behind a
  structural cast while the compatible SDK remains API 12. Feature-detect it or
  provide an API-12 fallback.

**2026-07-27 status:** the dev product now requires API 23, so this finding's
API-12 fallback premise no longer applies. The structural adapter can be removed
in a later typed-API cleanup after the API 23 HAP build is verified.

- Renderer extraction uses only the base codepoint instead of Ghostty's full
  grapheme buffer in multiple render/copy/search paths (`terminal.cpp:1982-1995,
  2206-2259`), breaking combining accents, variation selectors, and emoji ZWJ
  sequences.
- The NativeWindow path maps a dequeued buffer without waiting on the release
  fence returned by RequestBuffer, then passes that same descriptor back as
  FlushBuffer's acquire fence
  (`native_drawing_renderer.cpp:540-564,1103-1108`).
- Neither N-API module registers environment cleanup hooks for native sessions,
  threads, async work, hosts, or TSFNs.
- Native resize is queued to the render thread, but ArkTS immediately reads and
  reports the old terminal grid; no completion notification follows
  (`napi_init.cpp:1575-1582,2442-2449`, `TerminalController.ets:395-400`).
- OSC 9 notification parsing assumes a complete escape sequence in one native
  read, so split chunks can lose task-finished notifications
  (`napi_init.cpp:1648-1665`).

**2026-07-21 status — open after stability rollback:** device testing still
reported stutter with the proposed fence wait and native output consumer. Both
were removed together to restore the last known stable rendering/output path.
The original fence-lifecycle finding remains unresolved and needs an isolated,
profiled device fix.

**2026-07-27 status:** the fullscreen+focused tmux freeze was root-caused
separately: partial FlushBuffer dirtyRegion frames are not presented when the
surface is promoted to hardware direct composition. Dev now always reports
whole-surface damage (incremental blit retained). This is distinct from the
fence-lifecycle finding, which stays open.

## Verification Performed On 2026-07-10

- Current working tree: all 30 `tools/check-*.mjs` scripts passed.
- Clean `git archive HEAD`: 29 passed, one failed because the ignored
  `docs/粘贴板Debug.p7b` file was absent.
- Exact libssh2 tag commit queried against OSV on 2026-07-10.
- Source paths and lifecycle call chains were reviewed across ArkTS, N-API,
  PTY/SSH/SFTP, renderer, manifests, and build scripts.

The local environment does not provide `ohpm`, Hvigor, Harmony SDK, or `hdc`, so
the review could not perform a fresh HAP build, codelinter run, API-12 device
test, release signing test, or native sanitizer run.

## Recommended Repair Order

1. Remove/disable vulnerable SSH for release, then upgrade libssh2 and implement
   shared host-key verification.
2. Harden Agent pairing, credential storage, transport security, reconnect, and
   heartbeat behavior.
3. Fix the cross-tab image-upload profile bug and modal input leak.
4. Make native writes lossless and propagate PTY/SSH lifecycle events.
5. Add final renderer-host disposal and process-level native cleanup.
6. Repair keep-alive concurrency and the remaining connection-state races.
7. Make clean-clone build, signing, and tests reproducible before device QA.
8. Run the full Direction A, background/screen policy, and long-output device
   matrix before promoting dev changes into the release worktree.
