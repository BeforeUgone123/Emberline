# Emberline Product Positioning

## One-Line Position

Emberline is a HarmonyOS developer terminal for connecting to the Fusion
Development Engine Linux VM with a Ghostty-grade renderer and a native-feeling
ArkUI shell.

## Target User

The first target user is a HarmonyOS developer or power user working from a
HarmonyOS NEXT / 2-in-1 environment who needs a reliable terminal into the
Fusion Development Engine Linux VM.

This user values:

- fast access to a usable shell inside the Fusion VM;
- truecolor and 256-color rendering for modern CLI tools;
- hardware-keyboard ergonomics with a native key encoder and no soft key row;
- resize behavior that matches terminal expectations;
- clear separation between renderer library and app session logic.

## Product Thesis

A full Ghostty GUI port is the wrong first product. HarmonyOS has different app
shell, rendering surface, input, sandbox, and process constraints. The practical
product is a HarmonyOS app that reuses `libghostty-ohos` for terminal rendering
and implements the session layer natively for HarmonyOS.

The first durable value is not "run every local shell command on every device".
It is "make the Fusion Development Engine Linux VM feel one tap away from a
native terminal".

The preferred VM transport is now a `ystyle/wand-agent`-compatible WebSocket
PTY: a small agent runs inside the Fusion VM, owns Linux PTY creation, and
streams terminal bytes to the HarmonyOS app. SSH remains a fallback and later
advanced mode, not the default product promise.

## Primary Product Path

The primary path is a working VM terminal:

- first screen is the terminal workspace;
- the 48 vp rail keeps only connection, settings, and overflow after the session
  tabs;
- connection opens the `连接` destination of a three-part overlay inspector;
- default agent endpoint is the Fusion Development Engine VM bridge,
  `ws://172.16.100.2:8765/ws` with token `harmonyterm`;
- Fusion Agent creates a remote PTY in the Fusion VM;
- remote environment advertises `TERM=xterm-256color` and
  `COLORTERM=truecolor`;
- input, output, and resize round-trip through WebSocket binary
  frames and protocol control messages;
- rendering goes through `libghostty-ohos` and `libghostty_vt.a`.

The shell follows the Harmony Native Workbench direction: no standalone
onboarding page, no soft key row, no dashboard, and no terminal reflow
animation. Decision 2026-08-01 adds one persisted first-launch wand-agent
deploy/connect prompt over the already-mounted terminal; the same walkthrough
remains available from overflow rather than occupying permanent chrome.

## Secondary Paths

SSH/SFTP and local PTY are secondary capabilities. Local PTY remains
opportunistic where the HarmonyOS sandbox permits it. SSH/SFTP remains a
development fallback only until the dependency, shared host-key verification,
credential isolation, and lifecycle blockers in
[`code-review-2026-07-10.md`](code-review-2026-07-10.md) are resolved. Neither
path defines the product promise.

## Non-Goals

- Do not port Ghostty desktop GUI directly.
- Do not rewrite terminal rendering from scratch.
- Do not position this milestone as a general-purpose SSH manager.
- Do not turn image transfer into a general file manager or SFTP browser.
- Do not add app-owned terminal multiplexing, SSH agent, or key management
  before the VM terminal path is stable.
- Do not expose Fusion Agent broadly without stronger authentication and TLS or
  tunneling.
- Do not persist passwords.
- Do not blend in unrelated AI note-taking, Obsidian-like, PPT/PDF annotation,
  or lifestyle-app ideas from earlier HarmonyOS brainstorming threads.

## Success Criteria

- DevEco sync and HAP build succeed on a Harmony SDK machine.
- The app opens directly to a terminal workspace.
- The VM path connects to Fusion Agent through the default Fusion Development
  Engine VM bridge or a user-provided VM address.
- `echo "$TERM $COLORTERM"` reports `xterm-256color truecolor` inside the
  remote shell.
- A truecolor smoke command renders visibly distinct color output.
- Resize updates remote terminal dimensions.
- Ctrl-C, Ctrl-D, Tab, Esc, arrows, PgUp, and PgDn work through hardware input.
- Agent authentication is hardened before the endpoint is exposed outside the
  trusted VM bridge network.
- Known-host verification exists before the SSH fallback is treated as a broad
  SSH client.
- The development and release worktrees retain distinct bundle identities and
  signing inputs; release is built from `main`, not by swapping signing inside
  the dev tree.

## Naming

`Emberline` is both the GitHub repository name and the current app/product name
in source, README, and UI resources. Earlier project notes may refer to the
app as `FusionTerm` or to the repository as `HMG`.
