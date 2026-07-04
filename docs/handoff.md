# FusionTerm Handoff

## Source Thread

Primary discussion thread:

```text
/home/user/.codex/sessions/2026/07/02/rollout-2026-07-02T15-16-20-019f21af-8a93-76b1-b60d-e2122790c83a.jsonl
```

This is the thread where the product direction moved from Ghostty migration
research to a HarmonyOS advanced terminal project. The important decisions were:

- avoid a full desktop Ghostty GUI port;
- use `libghostty-ohos` as the HarmonyOS renderer/HAR;
- build a standalone HarmonyOS Stage app rather than bloating the renderer
  example app;
- target terminal use first, not note-taking or AI document workflows;
- prioritize connecting to the Fusion Development Engine Linux VM;
- prefer a `ystyle/wand-agent`-compatible WebSocket PTY as the default VM
  transport;
- keep SSH remote PTY as fallback rather than the first product path;
- keep local PTY as a fallback/prototype;
- create the project under `/mnt/linux_share/preview/harmony-advanced-terminal`;
- publish the repository as `HMG`.

Related exploratory threads:

- `019e8d39-437f-7260-9b63-895bad7f4138`: HarmonyOS ecosystem-gap discussion,
  including Obsidian-like note and AI folder-reading ideas.
- `019ea70e-87d9-76f1-831e-414bae920875`: broader HarmonyOS project
  brainstorming; those ideas are explicitly out of scope for HMG.

## Current State

The project is a HarmonyOS Stage scaffold with:

- app module `entry`;
- vendored renderer HAR module `libghostty_ohos`;
- prebuilt `libghostty_ohos/prebuilt/arm64-v8a/libghostty_vt.a`;
- first-screen ArkUI terminal workspace in `Index.ets`;
- `TerminalSurface` and `TerminalController` from `libghostty-ohos`;
- native N-API bridge in `entry/src/main/cpp/terminal_driver.cpp`;
- local PTY helper in `entry/src/main/cpp/pty`;
- SSH remote PTY helper in `entry/src/main/cpp/ssh`;
- password-based SSH prototype;
- startup 256-color renderer mock before the user opens a live session;
- terminal font fallback across Harmony/Noto/CJK plus Apple-family names when
  present on the device or imported into the system;
- optional app-bundled terminal fonts from
  `libghostty_ohos/src/main/resources/rawfile/fonts`; licensed files such as
  `PingFangSC-Regular.otf`, `PingFangSC-Regular.ttf`, `PingFangSC.ttf`, or
  `PingFang.ttc` are loaded before platform fallbacks when present;
- bundled open terminal fonts: Sarasa Fixed SC, JetBrains Mono, Cascadia Mono,
  and Symbols Nerd Font Mono; source and license notes live in
  `docs/third-party-fonts.md`;
- hidden ArkUI `TextInput` IME anchor inside `TerminalSurface` so HarmonyOS can
  recognize terminal typing as text input and open the system input method;
- Ghostty mouse encoder forwarding for terminal mouse reporting, including
  tmux pane selection and wheel events when `set -g mouse on` is active;
- wand-agent compatibility contract in `docs/fusion-agent-protocol.md`;
- Fusion Agent ArkTS client in `entry/src/main/ets/drivers/FusionAgentDriver.ets`;
- `ohos.permission.INTERNET` declared for VM network transports.

## Known Limits

- Full HAP build has not been verified in this Codex workspace because the
  local HarmonyOS SDK tools are not installed here.
- `third_party/libssh2` and `third_party/mbedtls` are not committed. Run
  `bash tools/fetch-third-party.sh` before native SSH builds.
- Fusion Agent's app-side client is implemented; the VM-side `wand-agent` or
  hardened project fork still needs to run inside the Fusion Development Engine
  Linux VM.
- Host-key verification is not implemented yet.
- Passwords are currently kept only in UI/runtime state, but the model still
  carries a `password` field. Refactor before adding persistence.
- The ArkUI workspace is still in one page file; component split is planned.
- Local PTY may be blocked or degraded by HarmonyOS sandbox behavior.
- Driver lifecycle still needs hardening around blocked reads and cleanup hooks.

## Build Handoff

On a DevEco/Harmony SDK machine:

```sh
bash tools/fetch-third-party.sh
ohpm install --all
hvigorw assembleHap --mode module -p product=default -p module=entry@default --no-daemon
```

If DevEco reports `libghostty_vt.a` missing, confirm this file exists:

```text
libghostty_ohos/prebuilt/arm64-v8a/libghostty_vt.a
```

If SSH native build fails, inspect:

- `entry/src/main/cpp/CMakeLists.txt`;
- `third_party/libssh2`;
- `third_party/mbedtls`;
- Harmony native SDK CMake toolchain paths in the DevEco error output.

## Recommended Next Steps

1. Verify DevEco sync and HAP build with the vendored HAR and prebuilt VT
   static library.
2. Run `wand-agent` or a hardened project fork inside the Fusion Development
   Engine Linux VM with token `harmonyterm`.
3. Verify the app can reach the agent at `172.16.100.2:8765/ws`, or update
   `DEFAULT_FUSION_AGENT_HOST` to the actual VM bridge address.
4. Keep SSH connection UI as fallback and add SSH host-key fingerprint
   extraction before broad SSH positioning.
5. Remove password from persisted/profile model boundaries.
6. Add settings/profile stores only after password handling is separated.
7. Split UI into `TopBar`, `ConnectionSheet`, and settings components.
8. Add manual QA scripts for truecolor, resize, keyboard, paste, tmux mouse, and
   reconnect behavior.

## 2026-07-03 Font / UI / Terminal-Correctness Pass

An uncommitted working-tree pass (Claude Code session over SSH) changed:

- **Default font now Maple Mono Normal NF CN** (`v7.9`, OFL), bundled at
  `libghostty_ohos/src/main/resources/rawfile/fonts/MapleMonoNormal-NF-CN-Regular.ttf`
  to mirror the developer's desktop Ghostty font stack. The renderer now
  registers every bundled font under its own family and walks a ghostty-style
  fallback chain (Maple → JetBrains Mono → Nerd Symbols → Cascadia → Sarasa →
  optional private fallback → platform). Text style locale switched from
  `en-US` to `zh-Hans` so CJK glyph variants resolve to Simplified Chinese
  forms. Font extraction now skips rewriting unchanged files on startup.
- **Physical keyboard encoding** (`napi_init.cpp BuildKeySequence`): arrows and
  Home/End honor DECCKM application cursor mode and xterm modifier codes
  (`CSI 1;m X`); Delete/Insert/PgUp/PgDn/F5-F12 carry modifiers (`CSI n;m ~`);
  Shift+Tab sends backtab `CSI Z`; Ctrl-Space/[/\/]/6/-//" map to C0 controls;
  Alt prefixes ESC including Ctrl+Alt chords, Alt+Enter/Backspace.
- **Bracketed paste**: new `Terminal::pasteText` uses `ghostty_paste_encode`
  (strips unsafe bytes, wraps in `ESC[200~..201~` when mode 2004 is set),
  exposed as `pasteText` through the N-API bridge and
  `TerminalController.paste`; the context-menu paste path uses it.
- **UTF-8 stream integrity**: both output paths no longer corrupt multi-byte
  characters split across read chunks — `FusionAgentDriver.decodeUtf8` buffers
  the incomplete tail between WebSocket frames, and the native driver's
  `EmitOutput` holds back trailing partial sequences before crossing the
  N-API string boundary.
- **Fusion Agent session state**: WebSocket handlers are guarded per socket
  instance (late events from a replaced socket can no longer pollute a new
  session); `exit` now tears the socket down before reporting, so input cannot
  be written into a dead shell. The 2026-07-03 jscrash
  (`status.label`/`error` undefined at `Index.ets:51`) was already fixed in
  the working tree by null-safe `formatStatusLabel`/`emitStatus`.
- **UI**: aligned with desktop Ghostty — near-black chrome (`#050507`
  surface via the adjusted Catppuccin_Mocha theme file), ghostty-style window
  padding (14/12) around the terminal surface, bar cursor without blink,
  font-size 13, real status dot instead of `*`/`o`, scrim + card connection
  panel with field labels. The bottom quick-key bar was removed entirely
  (2026-07-03 user decision: desktop-class terminal, physical keyboard only);
  the theme file also carries the Ghostty profile's selection colors.
- **Box drawing**: corner strokes overlap at the cell center so `┌`-style
  joints no longer show a notch.

Everything above still needs a DevEco build + on-device pass (font rendering,
IME, external keyboard, tmux mouse) — this workspace has no HarmonyOS
toolchain.

## 2026-07-03 Customization / Multi-Window / Mouse-Drag Pass

A second uncommitted pass (same Claude Code session) added:

- **Custom font import**: Settings panel imports a user `.ttf`/`.otf` via
  DocumentViewPicker into `filesDir/fonts/`, registered at runtime as
  `FusionTerm Custom` at the head of the renderer fallback chain
  (`registerCustomFont` through renderer -> N-API -> `TerminalController`);
  glyph cache is rebuilt and the grid re-measured. Reset requires an app
  restart to fully drop the registered family.
- **Background image + acrylic blur + opacity**: PhotoViewPicker copies the
  image into the sandbox; it renders behind the terminal with adjustable
  ArkUI `blur` (0-60) and the terminal surface honors ghostty
  `background-opacity` semantics — only default-background cells go
  translucent (`bgOpacity` through TerminalConfig -> renderer; opaque when no
  image is set). Chrome/panel colors stay opaque. NOTE: relies on
  XComponent SURFACE alpha compositing; if the device shows black instead of
  the image, switch the XComponent to TEXTURE type and re-verify.
- **Appearance persistence**: `entry/src/main/ets/settings/AppearanceStore.ets`
  (`@ohos.data.preferences`) stores font size, theme, custom font path,
  background path, opacity, and blur; restored on launch.
- **Multi-window**: `EntryAbility` is now `launchType: multiton` with a `+`
  button (startAbility on self) so each window is an independent terminal,
  matching desktop Ghostty windows. The entry native driver was de-globalized
  into a session registry (`createSession`/`destroySession`, all N-API calls
  take a sessionId) so concurrent windows cannot stomp each other's PTY/SSH.
- **tmux mouse drag**: external-mouse drag motions now report the held button
  (xterm button-motion encoding) so tmux pane splitters can be dragged; while
  an app tracks the mouse, touch is synthesized as a mouse — tap = left
  click, long-press then drag = button drag (pane resize), plain swipe =
  wheel scrolling.
- Settings panel replaces the top-bar theme toggle (`Cfg` button); top bar is
  now `+ / VM / Local / Cfg`.

All of it still needs the DevEco build + on-device pass; the multi-window
path additionally needs a check that windows share the process cleanly and
the surface-alpha check above.

## 2026-07-03 Hardened wand-agent Fork

The VM backend now has a hardened fork: `beforeugone520/wand-agent`
(commit `2974ee3`, upstream `ystyle/wand-agent` v0.2.3). Fixes: frame-type
routing (binary -> PTY, text -> control), single serialized WebSocket writer,
Bearer auth + constant-time compare + Origin allowlist + default bind
127.0.0.1, process-group teardown with an explicit `exit` event,
real `--host/--port/--max-sessions`, no agent-side bracketed paste,
protocol-level ping/pong heartbeat with read deadlines, `fork` removed.
End-to-end Go tests live in `main_test.go` (auth / shell round-trip /
frame routing / session limit / exit event) and pass on the openEuler VM.
The binary is installed at `/usr/local/bin/wand-agent` on the VM; run it as:

```sh
wand-agent --host 172.16.100.2 --token harmonyterm
```

`FusionAgentDriver.connect` now also sends `Authorization: Bearer <token>`
(query token kept for stock-agent compatibility).

## Do Not Drift

Keep the product focused on the Fusion VM terminal path. Earlier brainstorming
included AI note apps, PPT/PDF annotation, and lifestyle products, but those are
not part of HMG unless the user explicitly reopens that scope.
